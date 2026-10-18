(() => {
  const runId = __RUN_ID__;
  const delayMs = __DELAY_MS__;
  if (!/(^|\.)tuxun\.fun$/.test(location.hostname)) return JSON.stringify({error:'当前页面不是图寻'});
  if (!window.__tuxunStandalone || window.__tuxunStandalone.id !== runId) {
    // Replace the earlier Codex-injected interval if this page still has one.
    if (window.__coordTimer) clearInterval(window.__coordTimer);
    window.__coordStop = true;
    window.__tuxunStandalone = {id:runId, rounds:{}, events:[], sequence:0};
  }
  const state = window.__tuxunStandalone;
  const event = (message, extra={}) => {
    state.events.push({id:++state.sequence, time:new Date().toISOString(), message, ...extra});
    if(state.events.length>100) state.events.shift();
  };
  function model() {
    const element = document.querySelector('.maplibregl-map');
    let fiber = element?.[Object.keys(element).find(k=>k.startsWith('__reactFiber'))];
    let fallback;
    while(fiber) {
      for(let hook=fiber.memoizedState;hook;hook=hook.next) {
        const value=hook.memoizedState;
        // Ref.current tracks the active React render; memoizedState can be stale.
        if(value?.current?.onConfirm && value.current.gameData) return value.current;
        if(value?.onConfirm && value.gameData) fallback=value;
      }
      fiber=fiber.return;
    }
    return fallback;
  }
  const m=model();
  const text=document.body.innerText;
  if(!m) {
    const resultRound=text.match(/排位赛\s*-\s*第\s*(\d+)\s*\/\s*(\d+)\s*轮/);
    const ended=/失败！|胜利！|游戏结束|最终排名/.test(text) || (resultRound&&Number(resultRound[1])===Number(resultRound[2]));
    return JSON.stringify({waiting:!ended,done:!!ended,events:state.events,text:text.slice(0,1000)});
  }
  const game=m.gameData;
  const round=game.rounds?.find(r=>r.round===m.currentRound);
  const summary={gameId:game.id, round:m.currentRound, total:game.roundNumber, status:game.status};
  if(game.status!=='ongoing') return JSON.stringify({...summary,done:true,events:state.events,text:text.slice(0,1000)});
  if(!round || round.endTime) return JSON.stringify({...summary,done:!!(round?.endTime&&game.roundNumber>0&&m.currentRound>=game.roundNumber),events:state.events,text:text.slice(0,1000)});
  const key=game.id+':'+round.round;
  let rec=state.rounds[key];
  if(m.confirmed) {
    if(rec&&!rec.confirmed){rec.confirmed=true;event(rec.phase==='clicked'?'游戏已确认脚本提交':'本轮页面已显示提交状态',{round:round.round});}
    return JSON.stringify({...summary,events:state.events});
  }
  if(!rec) {
    rec=state.rounds[key]={phase:'fetching',created:Date.now()};
    const endpoint=round.source==='qq_pano'?'getQQPanoInfo':'getPanoInfo';
    function coordinates() {
      if(round.source==='google_pano') {
        return new Promise((resolve,reject)=>{
          const timer=setTimeout(()=>reject(Error('Google 全景信息请求超时')),12000);
          new google.maps.StreetViewService().getPanorama({pano:round.panoId},(data,status)=>{
            clearTimeout(timer);
            if(status!=='OK'||!data?.location?.latLng)return reject(Error('Google 全景接口：'+status));
            resolve({success:true,data:{lat:data.location.latLng.lat(),lng:data.location.latLng.lng()}});
          });
        });
      }
      if(!['baidu_pano','qq_pano'].includes(round.source))return Promise.reject(Error('暂不支持的全景来源：'+round.source));
      return fetch('/api/v0/tuxun/mapProxy/'+endpoint+'?pano='+encodeURIComponent(round.panoId),{signal:AbortSignal.timeout(12000)})
        .then(response=>{if(!response.ok)throw Error('HTTP '+response.status);return response.json()});
    }
    event('读取全景坐标',{round:round.round});
    coordinates()
      .then(result=>{
        if(window.__tuxunStandalone?.id!==runId)return;
        const data=result.data;
        if(!result.success||!Number.isFinite(data?.lat)||!Number.isFinite(data?.lng))throw Error('全景 API 未返回有效经纬度');
        rec.lat=data.lat;rec.lng=data.lng;rec.phase='ready';rec.readyAt=Date.now();
        event('已读取坐标，开始等待',{round:round.round,lat:rec.lat,lng:rec.lng,delaySeconds:delayMs/1000});
      })
      .catch(error=>{rec.phase='error';rec.error=String(error);event('读取失败',{round:round.round,error:rec.error})});
  } else if(rec.phase==='ready') {
    // A synchronous state setter is the same setter used by the game's map.
    m.setPickCoord({latitude:rec.lat,longitude:rec.lng});
    rec.phase='waiting';
  } else if(rec.phase==='waiting') {
    if(Date.now()-rec.readyAt>=delayMs) {
      if(!m.pickCoord || Math.abs(m.pickCoord.latitude-rec.lat)>1e-8 || Math.abs(m.pickCoord.longitude-rec.lng)>1e-8) {
        m.setPickCoord({latitude:rec.lat,longitude:rec.lng});
      } else {
        const button=[...document.querySelectorAll('button')].find(b=>b.innerText.trim()==='确定选择');
        if(button&&!button.disabled){
          button.click();rec.phase='clicked';rec.clickedAt=Date.now();rec.attempts=(rec.attempts||0)+1;
          event('已点击确定选择',{round:round.round,waitSeconds:Math.round((Date.now()-rec.readyAt)/100)/10});
        }
      }
    }
  } else if(rec.phase==='clicked'&&Date.now()-rec.clickedAt>5000) {
    if(rec.attempts<3)rec.phase='waiting';
    else{rec.phase='error';event('提交未获确认，请检查游戏页面',{round:round.round});}
  } else if(rec.phase==='fetching'&&Date.now()-rec.created>15000) {
    rec.phase='error';event('全景请求超时',{round:round.round});
  }
  return JSON.stringify({...summary,phase:rec.phase,events:state.events});
})()
