"""Build the Fulvia's own bank from Rally Trophy car_13.bzf.
Native recordings remain byte-identical. Coast/lift and gearbox approximations
are marked separately and never described as additional original recordings.
"""
from pathlib import Path
import sys,json,hashlib,wave,io
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
SOURCE=Path(r'D:\games\rally-throphy\Program Files\JoWooD\Rally Trophy\Data\Cars\car_13.bzf')
BANK=ROOT/'game/sounds/banks/FulviaHF'
sys.path.insert(0,r'D:\games\rally-throphy\stage_exporter\tools')
from bzf import read_bzf

def sha(data):return hashlib.sha256(data).hexdigest()
def pcm(data):
 with wave.open(io.BytesIO(data),'rb') as w:
  rate=w.getframerate();channels=w.getnchannels();width=w.getsampwidth();raw=w.readframes(w.getnframes())
 assert width==2, 'PCM16 expected'
 return np.frombuffer(raw,dtype='<i2').astype(np.float64).reshape(-1,channels).mean(axis=1)/32768,rate

def encode(x,rate):
 b=io.BytesIO()
 with wave.open(b,'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes((np.clip(x,-.98,.98)*32767).astype('<i2').tobytes())
 return b.getvalue()

def main():
 BANK.mkdir(exist_ok=True,parents=True);data=read_bzf(SOURCE);samples=[]
 def store(name,blob,origin,source=None):
  (BANK/name).write_bytes(blob);x,rate=pcm(blob);rms=float(np.sqrt(np.mean(x*x)));samples.append({'file':name,'sha256':sha(blob),'origin':origin,'source_file':source or name,'rate_hz':rate,'channels':1,'seconds':len(x)/rate,'rms':rms,'gain':min(.12/max(rms,.001),3.0),'space':{'eq':{'enabled':False}}})
 for name,blob in data.items():
  if name.lower().endswith('.wav'):store(name,blob,'native_byte_identical')
 # Closed-throttle timbre is a periodic low-pass derivation, retaining source pitch.
 for prefix in ['EE','EX']:
  for suffix in ['2k5','4k5','7k5']:
   name=f'{prefix}_{suffix}.wav';x,rate=pcm(data[name]);freq=np.fft.rfftfreq(len(x),1/rate);spectrum=np.fft.rfft(x);filtered=np.fft.irfft(spectrum/(1+(freq/1700)**4),n=len(x));store(f'{prefix}_coast_{suffix}.wav',encode(filtered,rate),'derived_lowpass_coast_approximation',name)
 # Generic gearbox tone, explicitly synthesized instead of reusing Escort samples.
 rate=22050;t=np.arange(rate*2)/rate
 for name,hz in [('fulvia_whine_low.wav',360),('fulvia_whine_high.wav',720)]:
  x=sum((.10/(i*i))*np.sin(2*np.pi*hz*i*t) for i in range(1,5));store(name,encode(x,rate),'synthesized_generic_gearbox_approximation')
 x,rate=pcm(data['EX_7k5.wav']);n=int(rate*.16)
 for i in range(3):
  start=min(i*int(rate*.07),max(len(x)-n,0));grain=np.resize(x[start:start+n],n);envelope=np.exp(-np.arange(n)/(rate*.032))*np.minimum(np.arange(n)/(rate*.0015),1);store(f'fulvia_lift_{i+1}.wav',encode(grain*envelope*1.5,rate),'derived_exhaust_lift_approximation','EX_7k5.wav')
 lookup={s['file']:s for s in samples};base='res://sounds/banks/FulviaHF/'
 def definition(name,ref,lower,upper,mode):return {'path':base+name,'reference':ref,'lower':lower,'upper':upper,'mode':mode,'gain':lookup[name]['gain']}
 def driven(prefix,idle):return [definition(idle,1100,0,2000,'idle')]+[definition(f'{prefix}_{suffix}.wav',ref,lower,upper,'drive') for suffix,ref,lower,upper in [('2k5',2000,700,4000),('4k5',3000,1800,6000),('7k5',5000,3000,11000)]]
 def coast(prefix):return [definition(f'{prefix}_coast_{suffix}.wav',ref,lower,upper,'coast') for suffix,ref,lower,upper in [('2k5',2000,500,4000),('4k5',3000,1800,6000),('7k5',5000,3000,11000)]]
 manifest={'schema_version':1,'vehicle_id':'lancia_fulvia_1600_hf','source_archive':str(SOURCE),'source_archive_sha256':sha(SOURCE.read_bytes()),'generator':str(Path(__file__).relative_to(ROOT)),'source_settings_sha256':sha(data['Sounds.ini']),'rpm_mapping':'Drive centres 2000/3000/5000 taken from Sounds.ini normalized RPM; idle 1100 and overlap ranges adapted to simulator profile. Not a measured recording-RPM analysis.','notes':['8 original engine/exhaust PCM files retained byte-for-byte','6 filtered coast loops and 3 enveloped lift events derived from native recordings','2 generic synthesized gearbox loops','No Escort engine or exhaust samples used'],'samples':samples,'engine':driven('EE','EE_Idle5.wav'),'exhaust':driven('EX','EX_Idle1.wav'),'coast_engine':coast('EE'),'coast_exhaust':coast('EX'),'whine':[base+'fulvia_whine_low.wav',base+'fulvia_whine_high.wav'],'backfire':[base+f'fulvia_lift_{i+1}.wav' for i in range(3)]}
 (BANK/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8');(BANK/'Sounds.ini').write_bytes(data['Sounds.ini'])
 print('FULVIA_BANK_READY',len(samples),'samples',sum(s['seconds'] for s in samples),'seconds')
if __name__=='__main__':main()
