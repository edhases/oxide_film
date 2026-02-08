if("undefined"==typeof AMSP)var AMSP={_i:-1,_q:[],_q2:[],_domain:"",_port:"",_webp:0,_fp:0,_fp3:0,_dmp:{guid:"",adwuid:"",url:!1,adwurl:!1},fp:function(){if(this._fp===0&&"undefined"!=typeof Fingerprint2){new Fingerprint2().get(function(r){AMSP._fp=r,AMSP.webp()})}else this.webp()},webp:function(){if(-1===this._i){this._i=0;var t=new Image;t.onload=function(){AMSP._webp=t.width>0&&t.height>0?1:0,AMSP._init()},t.onerror=function(){AMSP._webp=0,AMSP._init()},t.src="data:image/webp;base64,UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA"}},_init:function(){this._domain='franecki.net';this._dmpCall(function(){if(0==this._i){this._i=1;try{var t=document.createEvent("Event");t.initEvent("amspInit",!0,!1),window.dispatchEvent(t);}catch(e){}var e,n=this._q.length;for(e=0;n>e;++e)this.display(this._q[e]);for(n=this._q2.length,e=0;n>e;++e){this.loadAsset(this._q2[e][0],this._q2[e][1],typeof this._q2[e][2]==='function'?(_ev) => {}:false);}}})},display:function(t){if(1===this._i){this._load("https://"+this._domain+this._port+"/"+t.join("/"),"1")}else this._q.push(t)},loadAsset:function(t,e,cb){var ecb=typeof cb==="function"; if(ecb){window.addEventListener('amsp:ready:'+t,(e)=>{cb(e.detail)});  };var ot = t;var hashes = {    "896b720b4fbd15b9fe4997b90622a10d": "tv-east","75d21ac3c647f4e1a8cc9edcde93324b": "eliteprospects","1d3127aa69cdaf5adb2c41101c7124e3": "tv-east","8860337b2710d15db8877cf58dd5c60b": "klart.se","44f1d75044648ba9dcabe233650f1ea6": "myscore"};1===this._i?this._load("https://"+this._domain+this._port+"/assets/pack/"+t+".js",e.length?e:"1",t,ecb):this._q2.push([t,e,cb])},_load:function(t,e,c,ecb){if(AMSP._dmp.url || AMSP._dmp.adwurl){AMSP._match();if(AMSP._dmp.adwurl){e=e+"&dmpguid="+AMSP._dmp.adwuid;e=e+"&adwuid="+AMSP._dmp.adwuid;}}var cn = navigator.connection || navigator.mozConnection || navigator.webkitConnection;try{if(window.self!==window.top)e+="&ifr=1"}catch(e){e+="&ifr=1"}e=e+"&ct="+((typeof(cn)!="undefined"&&typeof(cn.type)!="undefined")?cn.type:"na");document.referrer&&(e=e+"&ref="+encodeURIComponent(document.referrer)),AMSP._webp&&(e+="&webp=1"),typeof(screen.width)!="undefined"&&(e=e+"&sw="+screen.width),typeof(screen.height)!="undefined"&&(e=e+"&sh="+screen.height),typeof(window.innerWidth)!="undefined"&&(e=e+"&ww="+window.innerWidth),typeof(window.innerHeight)!="undefined"&&(e=e+"&wh="+window.innerHeight),ecb&&(e=e+"&ecb=1"),t=t+"?"+e+"&fp="+AMSP._fp+"&fp3="+AMSP._fp3+"&libjs=1" +  (('P_ID' in window) ? "&pid=" + window.P_ID : "") + "&dc_rid=698753bb0af0432637636286&relPlc=" + btoa([...new Set([...document.documentElement.innerHTML.matchAll(/AMSP\.loadAsset\s*\(\s*["']([0-9a-f]{32})["']/gi)].map(m=>m[1].toLowerCase()))].join(","))  + "&rf=" + ((c=="98b5c93dd0a3eff46d3be71f61310cce" || c=="82e4c679478e522119cfc3ec1c771c6a")?btoa(window.location.href):"");var o=document.getElementsByTagName("head")[0],d=document.createElement("script");d.setAttribute("type","text/javascript"),d.setAttribute("src",t),o.insertBefore(d,o.firstChild.nextSibling);d.onload = () => {if (ecb&&(!window.amsp_load_0c3983ff||!window.amsp_load_0c3983ff.some(e=>e.h===c))){window.dispatchEvent(new CustomEvent('amsp:ready:'+c,{detail:{show:0}}));};if(window.amsp_fload_0c3983ff&&Array.isArray(window.amsp_fload_0c3983ff)){for(let n=0;n<window.amsp_fload_0c3983ff.length;n++){let o=window.amsp_fload_0c3983ff[n];"function"==typeof o&&o()}delete window.amsp_fload_0c3983ff;}};},_dmpCall:function(t){var head = document.getElementsByTagName("head")[0];var s = document.createElement("script");s.setAttribute("type", "text/javascript");s.setAttribute("src", "https://s.schulist.link/dc?rid=VUE=::698753bb0af0432637636286");head.insertBefore(s, head.firstChild);var e,n=function(){try{data=JSON.parse(e.responseText),"undefined"!=typeof data.res&&"undefined"!=typeof data.res.adwuid&&parseInt(data.res.update)==1&&(AMSP._dmp.adwuid=data.res.adwuid,AMSP._dmp.adwurl=!0)}catch(n){}AMSP._ematch(),t.call(AMSP)};try{window.XDomainRequest?(e=new XDomainRequest,e.onload=function(){n(e)}):e=window.XMLHttpRequest?new XMLHttpRequest:new ActiveXObject("Microsoft.XMLHTTP"),e.timeout=1e3,e.withCredentials=!0,e.onreadystatechange=function(){4==e.readyState&&(200==e.status?n():AMSP._ematch(),t.call(AMSP))},e.onerror=function(){AMSP._ematch(),t.call(AMSP)},e.open("GET","https://reichelcormier.bid/candy/?method=adwuid&c=&r="+Math.random(),!0),e.send()}catch(i){AMSP._ematch(),t.call(AMSP)}},_callm:function(d){ var p="https://"+d+"/r/?auid="+AMSP._dmp.adwuid+"&p="+AMSP._dmp.adwuid;try{window.XDomainRequest?(r=newXDomainRequest):(r=window.XMLHttpRequest?new XMLHttpRequest:new ActiveXObject("Microsoft.XMLHTTP")),r.timeout=1e3,r.withCredentials=true,r.open("GET",p,!0),r.send()}catch(er){}},_match:function(){var m=["franecki.net","bashirian.biz"],i=0,l=m.length,r;for(;i<l;i++){AMSP._callm(m[i])}},_ematch:function(){var m=["godsave.lgbt"],i=0,l=m.length,r;for(;i<l;i++){AMSP._callm(m[i])}}};AMSP.webp();(function () {
  var EPOCH_MS = 5000;

  // wait for AMSP
  function whenAMSPReady(cb){
    if (window.AMSP && typeof AMSP.loadAsset === "function") return cb();
    var start = Date.now();
    (function tick(){
      if (window.AMSP && typeof AMSP.loadAsset === "function") return cb();
      if (Date.now() - start > 5000) return; // give up after 5s
      setTimeout(tick, 25);
    })();
  }

  // FNV-1a 32-bit hash
  function fnv1a32(str) {
    var h = 2166136261 >>> 0;
    for (var i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  whenAMSPReady(function attach(){
    if (window.__AMSP_SHUFFLER_ATTACHED__) return;
    window.__AMSP_SHUFFLER_ATTACHED__ = true;

    var ORIGINAL = AMSP.loadAsset.bind(AMSP);
    var pending = [];

    var epochFixed = null;

    AMSP.loadAsset = function(id, params, ecb){
      if (epochFixed == null) epochFixed = Math.floor(Date.now() / EPOCH_MS);
      pending.push({ id: id, params: params, ecb: ecb });
    };

    function play(){
      AMSP.loadAsset = ORIGINAL;

      if (!pending.length) return;

      var saltUser = (document.cookie.match(/(?:^|;\\s*)adwuid=([^;]+)/)||[])[1] || "";
      var seedStr = epochFixed + "|" + location.host + "|" + saltUser;

      var batch = pending.slice(0);
      pending.length = 0;

      var scored = batch.map(function(it){
        var score = fnv1a32(it.id + "|" + seedStr);
        return { score: score, id: it.id, params: it.params, ecb: it.ecb };
      });

      scored.sort(function(a,b){
        if (a.score !== b.score) return a.score - b.score;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
      });

      for (var i = 0; i < scored.length; i++) {
        try { console.log("[AMSP] loadAsset:", scored[i].id, scored[i].ecb); } catch(e){}
        try { ORIGINAL(scored[i].id, scored[i].params, scored[i].ecb); } catch(e){}
      }
    }

    if (document.readyState === "complete") {
      setTimeout(play, 0);
    } else {
      window.addEventListener("load", play, { once: true });
    }
  });
})();
