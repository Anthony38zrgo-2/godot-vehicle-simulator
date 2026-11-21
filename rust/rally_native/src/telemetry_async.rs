use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use godot::builtin::{GString, PackedFloat32Array, PackedInt32Array};
use godot::classes::RefCounted;
use godot::prelude::*;

const CHANNEL_CAPACITY: usize = 1024;
const EXPECTED_FLOATS: usize = 33;
const EXPECTED_INTS: usize = 4;

enum TelemetryMsg {
    Sample(Box<SampleRecord>),
    Flush,
    Finish {
        summary_path: String,
        summary_json: String,
    },
}

struct SampleRecord {
    utc_time: String,
    floats: [f32; EXPECTED_FLOATS],
    ints: [i32; EXPECTED_INTS],
    surfaces: [String; 4],
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct RustAsyncTelemetryWriter {
    sender: Option<SyncSender<TelemetryMsg>>,
    worker: Option<JoinHandle<()>>,
    run_id: String,
    dropped_samples: u64,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for RustAsyncTelemetryWriter {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            sender: None,
            worker: None,
            run_id: String::new(),
            dropped_samples: 0,
            base,
        }
    }
}

impl Drop for RustAsyncTelemetryWriter {
    fn drop(&mut self) {
        self.shutdown_worker(None);
    }
}

#[godot_api]
impl RustAsyncTelemetryWriter {
    #[func]
    pub fn start_session(
        &mut self,
        csv_abs_path: GString,
        header_line: GString,
        run_id: GString,
        metadata_abs_path: GString,
        metadata_json: GString,
        flush_every_seconds: f32,
    ) -> bool {
        self.shutdown_worker(None);
        self.dropped_samples = 0;

        let csv_path_str = csv_abs_path.to_string();
        if csv_path_str.is_empty() {
            return false;
        }
        if let Some(parent) = Path::new(&csv_path_str).parent()
            && !parent.as_os_str().is_empty()
            && let Err(err) = std::fs::create_dir_all(parent)
        {
            godot_error!("RustAsyncTelemetryWriter: failed to create dir: {err}");
            return false;
        }

        let file = match File::create(&csv_path_str) {
            Ok(f) => f,
            Err(err) => {
                godot_error!("RustAsyncTelemetryWriter: cannot open '{csv_path_str}': {err}");
                return false;
            }
        };

        let mut writer = BufWriter::with_capacity(64 * 1024, file);
        let header_str = header_line.to_string();
        if !header_str.is_empty()
            && let Err(err) = writeln!(writer, "{header_str}")
        {
            godot_error!("RustAsyncTelemetryWriter: failed to write header: {err}");
            return false;
        }

        let run_id_str = run_id.to_string();
        self.run_id = run_id_str.clone();
        let meta_path_str = metadata_abs_path.to_string();
        let meta_json_str = metadata_json.to_string();
        let flush_interval = Duration::from_secs_f32(flush_every_seconds.max(0.1));

        let (tx, rx) = mpsc::sync_channel::<TelemetryMsg>(CHANNEL_CAPACITY);
        let handle = thread::Builder::new()
            .name("rally-telemetry-io".to_string())
            .spawn(move || {
                if !meta_path_str.is_empty() && !meta_json_str.is_empty() {
                    let _ = std::fs::write(&meta_path_str, meta_json_str.as_bytes());
                }

                let mut last_flush = Instant::now();
                let mut line_buf = String::with_capacity(512);

                while let Ok(msg) = rx.recv() {
                    match msg {
                        TelemetryMsg::Sample(rec) => {
                            format_csv_line(&mut line_buf, &run_id_str, &rec);
                            let _ = writer.write_all(line_buf.as_bytes());
                            if last_flush.elapsed() >= flush_interval {
                                let _ = writer.flush();
                                last_flush = Instant::now();
                            }
                        }
                        TelemetryMsg::Flush => {
                            let _ = writer.flush();
                            last_flush = Instant::now();
                        }
                        TelemetryMsg::Finish {
                            summary_path,
                            summary_json,
                        } => {
                            let _ = writer.flush();
                            if !summary_path.is_empty() && !summary_json.is_empty() {
                                let _ = std::fs::write(&summary_path, summary_json.as_bytes());
                            }
                            return;
                        }
                    }
                }
                let _ = writer.flush();
            });

        match handle {
            Ok(h) => {
                self.sender = Some(tx);
                self.worker = Some(h);
                true
            }
            Err(err) => {
                godot_error!("RustAsyncTelemetryWriter: failed to spawn I/O thread: {err}");
                false
            }
        }
    }

    #[func]
    #[allow(clippy::too_many_arguments)]
    pub fn push_sample(
        &mut self,
        utc_time: GString,
        floats_in: PackedFloat32Array,
        ints_in: PackedInt32Array,
        s0: GString,
        s1: GString,
        s2: GString,
        s3: GString,
    ) -> bool {
        let Some(tx) = self.sender.as_ref() else {
            return false;
        };

        let mut floats = [0.0f32; EXPECTED_FLOATS];
        let f_slice = floats_in.as_slice();
        let f_copy = f_slice.len().min(EXPECTED_FLOATS);
        floats[..f_copy].copy_from_slice(&f_slice[..f_copy]);

        let mut ints = [0i32; EXPECTED_INTS];
        let i_slice = ints_in.as_slice();
        let i_copy = i_slice.len().min(EXPECTED_INTS);
        ints[..i_copy].copy_from_slice(&i_slice[..i_copy]);

        let rec = SampleRecord {
            utc_time: utc_time.to_string(),
            floats,
            ints,
            surfaces: [s0.to_string(), s1.to_string(), s2.to_string(), s3.to_string()],
        };

        match tx.try_send(TelemetryMsg::Sample(Box::new(rec))) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) => {
                self.dropped_samples += 1;
                false
            }
            Err(TrySendError::Disconnected(_)) => false,
        }
    }

    #[func]
    pub fn request_flush(&self) {
        if let Some(tx) = self.sender.as_ref() {
            let _ = tx.try_send(TelemetryMsg::Flush);
        }
    }

    #[func]
    pub fn finish_session(&mut self, summary_abs_path: GString, summary_json: GString) {
        let summary_path = summary_abs_path.to_string();
        let summary_body = summary_json.to_string();
        self.shutdown_worker(Some((summary_path, summary_body)));
    }

    #[func]
    pub fn get_dropped_samples(&self) -> i64 {
        self.dropped_samples as i64
    }

    #[func]
    pub fn is_active(&self) -> bool {
        self.sender.is_some()
    }
}

impl RustAsyncTelemetryWriter {
    fn shutdown_worker(&mut self, summary: Option<(String, String)>) {
        if let Some(tx) = self.sender.take() {
            if let Some((summary_path, summary_json)) = summary {
                let _ = tx.send(TelemetryMsg::Finish {
                    summary_path,
                    summary_json,
                });
            }
            drop(tx);
        }
        if let Some(handle) = self.worker.take() {
            let _ = handle.join();
        }
    }
}

#[inline]
fn format_csv_line(out: &mut String, run_id: &str, rec: &SampleRecord) {
    use std::fmt::Write;
    out.clear();
    let f = &rec.floats;
    let i = &rec.ints;
    let flags = i[3];
    let airborne = (flags & 1) != 0;
    let overturned = (flags & 2) != 0;
    let sleeping = (flags & 4) != 0;
    let stability = (flags & 8) != 0;
    let auto_tx = (flags & 16) != 0;

    let _ = writeln!(
        out,
        "{},{},{:.4},{},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.3},{:.1},{},{:.3},{:.3},{:.3},{:.3},{:.3},{},{},{},{},{:.2},{:.2},{:.2},{:.2},{},{},{},{},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.4},{:.3},{},{:.3},{:.3},{:.1},{}",
        run_id,
        rec.utc_time,
        f[0],  // elapsed_seconds
        i[0],  // physics_tick
        f[1],  // pos.x
        f[2],  // pos.y
        f[3],  // pos.z
        f[4],  // lin_vel.x
        f[5],  // lin_vel.y
        f[6],  // lin_vel.z
        f[7],  // ang_vel.x
        f[8],  // ang_vel.y
        f[9],  // ang_vel.z
        f[10], // speed_kmh
        f[11], // engine_rpm
        i[1],  // current_gear
        f[12], // throttle
        f[13], // brake
        f[14], // clutch
        f[15], // steering
        f[16], // true_steering
        i[2],  // contact_count
        airborne,
        overturned,
        sleeping,
        f[17], // comp FL
        f[18], // comp FR
        f[19], // comp RL
        f[20], // comp RR
        rec.surfaces[0],
        rec.surfaces[1],
        rec.surfaces[2],
        rec.surfaces[3],
        f[21], // slip FL lon
        f[22], // slip FL lat
        f[23], // slip FR lon
        f[24], // slip FR lat
        f[25], // slip RL lon
        f[26], // slip RL lat
        f[27], // slip RR lon
        f[28], // slip RR lat
        f[29], // traction_control_max_slip
        stability,
        f[30], // countersteer_assist
        f[31], // steering_slip_assist
        f[32], // anti_lock_brake_threshold
        auto_tx,
    );
}
