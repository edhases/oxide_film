new (function(){var StickerStates, __assign = this && this.__assign || function () {
    return (__assign = Object.assign || function (t) {
        for (var e, i = 1, n = arguments.length; i < n; i++) for (var o in e = arguments[i]) Object.prototype.hasOwnProperty.call(e, o) && (t[o] = e[o]);
        return t
    }).apply(this, arguments)
};

function isMobile() {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)
}

!function (t) {
    t[t.HIDDEN = 0] = "HIDDEN", t[t.VISIBLE = 1] = "VISIBLE", t[t.ANIMATING = 2] = "ANIMATING"
}(StickerStates = StickerStates || {});

var AdBranding = function () {
    function t(t) {
        if (this.stickerTransitionDuration = "240ms", !t) throw new Error("Config is not provided!");
        (this.config = t).contentSelector && (this.pageContent = document.querySelector(t.contentSelector)), t.headerSelector && (this.pageHeader = document.querySelector(t.headerSelector)), this.render(), this.setupMobileBranding()
    }

    return t.prototype.resize = function () {
        var i = this.getPageSizes(), n = {};
        Object.keys(i).forEach(function (t) {
            var e = i[t];
            -1 < e && (n[t] = e)
        }), this.sendToIframe(this.staticIframe.name, n), this.stickyIframe && this.sendToIframe(this.stickyIframe.name, __assign(__assign({}, n), { headerHeight: void 0 }))
    }, t.prototype.render = function () {
        var t = this;
        this.applyStyles(), this.renderStatic(), this.staticIframe.addEventListener("load", function () {
            return t.resize()
        }), isMobile() || (window.addEventListener("resize", function () {
            return t.resize()
        }), this.resize())
    }, t.prototype.renderStatic = function () {
        var t = document.createElement("noindex"), e = document.createElement("div");
        e.id = this.config.ad.divId, e.style.cssText = "\n            position: fixed;\n            overflow: hidden;\n            left: 0;\n            top: 0;\n            right: 0;\n            height: 100%;\n            z-index: 0;\n        ";
        var i = this.getPageSizes();
        e.innerHTML = this.config.ad.code.replace("{{contentWidth}}", i.contentWidth.toString()).replace("{{distanceToTop}}", i.distanceToTop.toString()).replace("{{headerHeight}}", i.headerHeight.toString()), t.appendChild(e), document.body.insertBefore(t, document.body.firstChild), this.staticIframe = document.querySelector("#i" + this.config.ad.divId)
    }, t.prototype.renderSticky = function () {
        var t = document.createElement("div");
        t.id = "sc" + this.config.ad.divId;
        var e = this.getPageSizes();
        t.style.cssText = "\n            position: fixed;\n            overflow: hidden;\n            left: 0;\n            right: 0;\n            top: 0;\n            height: " + this.config.ad.indent + "px;\n            transform: translateY(-100%);\n        ", this.stickerState = StickerStates.HIDDEN, t.innerHTML = this.config.ad.code.replace("{{contentWidth}}", e.contentWidth.toString()).replace("{{distanceToTop}}", e.distanceToTop.toString()).replace("{{headerHeight}}", e.headerHeight.toString()).replace("i" + this.config.ad.divId, "si" + this.config.ad.divId).replace("ni" + this.config.ad.divId, "sni" + this.config.ad.divId), document.body.appendChild(t), this.stickyIframe = document.querySelector("#si" + this.config.ad.divId), this.setupStickyBehavior()
    }, t.prototype.getPageSizes = function () {
        var t = { contentWidth: -1, headerHeight: -1, distanceToTop: -1 };
        return this.pageContent && (t.contentWidth = this.pageContent.offsetWidth, t.distanceToTop = this.pageContent.getBoundingClientRect().top + window.scrollY), this.pageHeader && (t.headerHeight = this.pageHeader.offsetHeight), t
    }, t.prototype.sendToIframe = function (t, e) {
        var i = window.frames[t];
        i && i.postMessage(e, "*")
    }, t.prototype.applyStyles = function () {
        var t = document.querySelector("head"), e = document.createElement("style");
        e.id = "brnd_styling", e.textContent = this.config.ad.styles, t.appendChild(e)
    }, t.prototype.onFadeComplete = function (t, e) {
        t.removeEventListener("transitionend", this.onFadeComplete.bind(this)), e && e()
    }, t.prototype.fadeOut = function (i) {
        var n = this;
        return i.style.transitionDuration = this.stickerTransitionDuration, i.style.transitionTimingFunction = "ease-in", new Promise(function (t, e) {
            i.addEventListener("transitionend", function () {
                n.onFadeComplete(i, t)
            }), i.style.transform = "translateY(-100%)"
        })
    }, t.prototype.fadeIn = function (i) {
        var n = this;
        return i.style.transitionDuration = this.stickerTransitionDuration, i.style.transitionTimingFunction = "ease-out", new Promise(function (t, e) {
            i.addEventListener("transitionend", function () {
                n.onFadeComplete(i, t)
            }), i.style.transform = "translateY(0%)"
        })
    }, t.prototype.setupStickyBehavior = function () {
        var i = this, n = document.querySelector("#sc" + this.config.ad.divId);
        window.addEventListener("scroll", function (t) {
            i.stickingTimeoutId && clearTimeout(i.stickingTimeoutId), i.stickingTimeoutId = window.setTimeout(function (t) {
                i.fadeOut(n).then(function () {
                    i.stickerState = StickerStates.HIDDEN
                })
            }, 3e3);
            var e = window.scrollY < i.getPageSizes().distanceToTop;
            i.stickerState !== StickerStates.HIDDEN || e || (i.stickerState = StickerStates.ANIMATING, i.fadeIn(n).then(function () {
                i.stickerState = StickerStates.VISIBLE
            })), i.stickerState === StickerStates.VISIBLE && e && (i.stickerState = StickerStates.ANIMATING, i.fadeOut(n).then(function () {
                i.stickerState = StickerStates.HIDDEN
            }))
        })
    }, t.prototype.setupMobileBranding = function () {
        function setupMobileBranding(isActive, id, height = 200, timeout = 1, offset = 500) {
            let isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
            if (!id) return console.error('not provide id');
        
            if (isMobile && isActive === '1') {
                let timeoutId;
                let lastScrollPosition = window.scrollY || document.documentElement.scrollTop;
                let brandContainer = document.getElementById(id);
        
                brandContainer.style.transition = "transform 0.5s ease";
                brandContainer.style.height = height + "px";
        
                window.addEventListener("scroll", () => {
                    clearTimeout(timeoutId);
                    brandContainer.style.transform = "translateY(0px)";
                    brandContainer.style.zIndex = 0;
        
                    let currentScrollPosition = window.scrollY || document.documentElement.scrollTop;
        
                    // Добавленное условие для случая, если scrollY меньше нуля
                    if (window.scrollY < 0) {
                        return brandContainer.style.transform = "translateY(0px)";
                    }
        
                    if (window.scrollY > height - 1 && window.scrollY < offset) {
                        if (currentScrollPosition > lastScrollPosition) {
                            // Прокрутка вниз
                            brandContainer.style.transition = "none"; // отключаем transition
                            brandContainer.style.transform = `translateY(-${height}px)`;
                            // принудительно перерисовываем элемент, чтобы изменения вступили в силу
                            brandContainer.offsetHeight;
                            brandContainer.style.transition = "transform 0.5s ease"; // включаем обратно transition
                        } else {
                            // Прокрутка вверх
                            brandContainer.style.transform = `translateY(0px)`;
                        }
                    }
        
                    if (window.scrollY > offset) {
                        brandContainer.style.zIndex = 1001;
        
                        timeoutId = setTimeout(function () {
                            brandContainer.style.transform = `translateY(-${height}px)`;
                        }, timeout * 1000);
                    }
        
                    lastScrollPosition = currentScrollPosition;
                });
            }
        }

        setupMobileBranding(this.config.ad.br_dynamic, this.config.ad.divId, this.config.ad.br_height, this.config.ad.br_timeout, this.config.ad.br_offset);
    }, t
}();
                const brnd = new AdBranding({
                        host: 'ad2the.net',
                        ad: {
                            id: 39173,
                            divId: 'brndb4f46b013',
                            br_dynamic: '0',
                            br_height: '150',
                            br_timeout: '400',
                            br_offset: '1',
                            clickUrl: '//bashirian.biz/content/static/48c51d1c8985801c89e2b75725bd13a7/39173.html?pauid=69875411067e812944873658&reqId=50e35e9e-e16c-48da-b536-906af27b5af1&external_domain=uafix.net&ct=4g',
                            bg: '',
                            indent: 0,
                            image: '//s.schulist.link/media/html5/0/8/8930409d-f18e-46ab-87a2-438969868917/index.html',
                            styles: 'body { padding: 0px 0 0 !important; }body > div, body > table, body > center { position: relative; margin: 0 auto; z-index: 3; }body.dark .main {background:rgb(31, 34, 35) !important;} .main{background: #f2f2f2;} .cont { padding: 30px 0 0; } .cont.center{overflow: hidden;} .cont{padding: 0 !important} .wrap { max-width: 1200px; background: white; } body { padding-top: 270px !important; } @media screen and (max-width: 1000px) { body { padding-top: 220px !important; }} .pages-bg { margin-top: 0px !important;; }',
                            code: '<iframe id="ibrndb4f46b013" name="nibrndb4f46b013" src="//s.schulist.link/iframeHS/39173/JTJGJTJGYmFzaGlyaWFuLmJpeiUyRmNvbnRlbnQlMkZzdGF0aWMlMkY0OGM1MWQxYzg5ODU4MDFjODllMmI3NTcyNWJkMTNhNyUyRjM5MTczLmh0bWwlM0ZwYXVpZCUzRDY5ODc1NDExMDY3ZTgxMjk0NDg3MzY1OCUyNnJlcUlkJTNENTBlMzVlOWUtZTE2Yy00OGRhLWI1MzYtOTA2YWYyN2I1YWYxJTI2ZXh0ZXJuYWxfZG9tYWluJTNEdWFmaXgubmV0JTI2Y3QlM0Q0ZyU3QyU3QyU3QyU3QyUyRiUyRnMuc2NodWxpc3QubGluayUyRm1lZGlhJTJGaHRtbDUlMkYwJTJGOCUyRjg5MzA0MDlkLWYxOGUtNDZhYi04N2EyLTQzODk2OTg2ODkxNyUyRmluZGV4Lmh0bWwlN0MlN0MlN0MlN0NicmFuZGluZyU3QyU3QyU3QyU3QzE1NzE3Mg%3D%3D?contentWidth={{contentWidth}}&amp;distanceToTop={{distanceToTop}}&amp;headerHeight={{headerHeight}}&amp;updated=1770422702" style="width:100%;height:100%"width="100%" height="100%" marginwidth="0" marginheight="0" frameborder="0" vspace="0" hspace="0"scrolling="no"></iframe>'
                        },
                        contentSelector: '.wrap',
                        headerSelector: '.header'
                    });
                (function(css){
                  const style = document.querySelector('style[data-adserver]') ||
                    (function(){const s=document.createElement('style');s.dataset.adserver='';document.head.appendChild(s);return s;})();
                  style.textContent = css;
                })("body.dark .main {background:rgb(31, 34, 35) !important;} .main{background: #f2f2f2;} .cont { padding: 30px 0 0; } .cont.center{overflow: hidden;} .cont{padding: 0 !important} .wrap { max-width: 1200px; background: white; } body { padding-top: 270px !important; } @media screen and (max-width: 1000px) { body { padding-top: 220px !important; }} .pages-bg { margin-top: 0px !important;; }");
            window.amsp_load_0c3983ff=window.amsp_load_0c3983ff||[];window.amsp_load_0c3983ff.push({h:"48c51d1c8985801c89e2b75725bd13a7",ts:Date.now()});
})();