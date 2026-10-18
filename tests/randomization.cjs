const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(require('node:path').join(__dirname,'../runner.js'),'utf8');
async function run(options,lat,lng,random=()=>0.5){
 let now=1000,clicks=0;
 const model={currentRound:1,confirmed:false,gameData:{id:'test',status:'ongoing',roundNumber:2,rounds:[{round:1,source:'baidu_pano',panoId:'test'}]},setPickCoord(p){this.pickCoord=p},onConfirm(){}};
 const el={__reactFiber$test:{memoizedState:{memoizedState:{current:model},next:null},return:null}};
 const math=Object.create(Math);math.random=random;
 const c=vm.createContext({Math:math,location:{hostname:'tuxun.fun'},window:{},document:{body:{innerText:''},querySelector:()=>el,querySelectorAll:()=>[{innerText:'确定选择',disabled:false,click(){clicks++;model.confirmed=true}}]},fetch:async()=>({ok:true,json:async()=>({success:true,data:{lat,lng}})}),AbortSignal,Date:class extends Date{static now(){return now}},clearInterval(){},setTimeout,clearTimeout});
 const code=source.replace('__RUN_ID__','"test"').replace('__OPTIONS__',JSON.stringify(options));
 const tick=()=>JSON.parse(vm.runInContext(code,c));
 tick();await new Promise(r=>setImmediate(r));tick();
 const rec=c.window.__tuxunStandalone.rounds['test:1'];
 const saved=JSON.stringify([rec.lat,rec.lng,rec.delayMs]);
 now=rec.readyAt+rec.delayMs-1;tick();assert.equal(clicks,0);
 now+=1;tick();assert.equal(clicks,1);tick();assert.equal(clicks,1);
 assert.equal(JSON.stringify([rec.lat,rec.lng,rec.delayMs]),saved);
 return rec;
}
function meters(a,b){const rad=x=>x*Math.PI/180;const p=rad(b.lat-a.lat),q=rad(b.lng-a.lng);return 6371008.8*2*Math.asin(Math.min(1,Math.sqrt(Math.sin(p/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(q/2)**2)));}
(async()=>{
 const base={delayMode:'fixed',delayMs:10000,delayMinMs:8000,delayMaxMs:15000,offsetMeters:0};
 const exact=await run(base,31,121);assert(Math.abs(exact.lat-31)<1e-10);assert(Math.abs(exact.lng-121)<1e-10);assert.equal(exact.delayMs,10000);
 for(const [lat,lng] of [[31,121],[89.999,179.999],[-89.999,-179.999],[0,179.999]]){
  const rec=await run({...base,delayMode:'random',offsetMeters:1000},lat,lng);
  assert.equal(rec.delayMs,11500);assert(Math.abs(meters({lat,lng},rec)-1000*Math.sqrt(.5))<.01);assert(rec.lat>=-90&&rec.lat<=90);assert(rec.lng>=-180&&rec.lng<180);
 }
 for(const value of [0,.999999]){
  const rec=await run({...base,delayMode:'random',offsetMeters:1000},0,0,()=>value);
  assert(rec.delayMs>=8000&&rec.delayMs<=15000);assert(meters({lat:0,lng:0},rec)<=1000.001);
 }
 console.log('PASS: fixed/random wait boundaries, stable per-round values, zero offset, radius bounds, poles and date line');
})().catch(e=>{console.error(e);process.exitCode=1});
