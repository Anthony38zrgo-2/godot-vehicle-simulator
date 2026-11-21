/// Deterministic PCG32 PRNG for particle emission, styling, and procedural textures.
#[derive(Clone, Debug)]
pub struct Pcg32 {
    state: u64,
    inc: u64,
}

impl Pcg32 {
    pub fn seeded(seed: u64) -> Self {
        let mut rng = Self {
            state: 0,
            inc: (seed << 1) | 1,
        };
        rng.next_u32();
        rng.state = rng.state.wrapping_add(seed);
        rng.next_u32();
        rng
    }

    #[inline]
    pub fn next_u32(&mut self) -> u32 {
        let old_state = self.state;
        self.state = old_state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(self.inc);
        let xorshifted = (((old_state >> 18) ^ old_state) >> 27) as u32;
        let rot = (old_state >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    #[inline]
    pub fn randf(&mut self) -> f32 {
        // 24-bit mantissa in [0.0, 1.0)
        ((self.next_u32() >> 8) as f32) / 16777216.0
    }

    #[inline]
    pub fn randf_range(&mut self, from: f32, to: f32) -> f32 {
        from + (to - from) * self.randf()
    }

    #[inline]
    pub fn randi_range(&mut self, from: i32, to: i32) -> i32 {
        if to <= from {
            return from;
        }
        let span = (to - from + 1) as u32;
        from + (self.next_u32() % span) as i32
    }
}
