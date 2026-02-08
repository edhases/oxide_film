new (function(){
this.host = "franecki.net";this.ad = {"id":139113,"divId":"b2481fe93d","divIdOld":"bb3a0386e7","width":600,"height":200,"image":"\/\/s.schulist.link\/media\/8\/1\/81303785100874_281.webp","alternateImage":"","clickUrl":"\/\/bashirian.biz\/content\/static\/5126fdc076a653ecdf73214ca4499b52\/139113.html?pauid=69875411067e812944873658&reqId=d6d37148-fc0a-49b2-9e24-779f24caed9c&external_domain=uafix.net&ct=4g"};
this.div = document.getElementById(this.ad.divId);
if (!this.div) {
    this.div = document.getElementById(this.ad.divIdOld);
}
//139113
if (!this.div) {
    console.log('container #' + this.ad.divId + ' not found!');
    return;
}
this.div.style.display = 'block';
this.div.style.height = this.ad.height+'px';
this.div.style.width = this.ad.width+'px';
this.div.style.cursor = 'pointer';
this.div.style.position = 'relative';
this.div.style.overflow = 'hidden';
this.div.style.maxWidth = '100%';
let wrapper = this.div;const throwAwayYourSmallResolutionedPhone = function() {
            const w = wrapper.getBoundingClientRect().width;
            if (w < 600) { 
                var ratio = (w/600);
                if(ratio>0.98){return;}
                wrapper.style.transform='scale('+ratio+')';
                wrapper.style.setProperty('transform-origin','0 0', 'important');
                const mW = 600/w*100;
                wrapper.style.setProperty('max-width', mW+'%', 'important');
                wrapper.style.setProperty('width', mW+'%', 'important');
                wrapper.style.setProperty('margin-bottom',Math.round(200*ratio - 200,0) + 'px', 'important');
                wrapper.style.setProperty('min-height', 200, 'important');
            }
        };        window.onload = throwAwayYourSmallResolutionedPhone;
throwAwayYourSmallResolutionedPhone();
if ('0px' != '0px') {
    this.div.style.margin = '0px';
} else {
    this.div.style.marginLeft = 'auto';
    this.div.style.marginRight = 'auto';
}

this.img = document.createElement('img');
this.img.src = this.ad.image;
this.img.style.maxHeight = this.ad.height+'px';
this.img.style.maxWidth = this.ad.width+'px';
this.img.style.display = 'block';
this.img.style.margin= '0 auto';

this.link = document.createElement('a');
this.link.href = this.ad.clickUrl + (this.ad.clickUrl.indexOf('?') >= 0 ? '&' : '?') + Math.random()
this.link.target = '_blank';
this.link.rel= 'nofollow';
this.link.style.display = 'block';
this.link.style.padding = '0';
this.link.style.margin = '0';

this.link.appendChild(this.img);
this.div.appendChild(this.link);

var AD = this.ad;
window.amsp_load_0c3983ff=window.amsp_load_0c3983ff||[];window.amsp_load_0c3983ff.push({h:"5126fdc076a653ecdf73214ca4499b52",ts:Date.now()});
})();