//14696
                (function () {
                    var strt = function() {
                        var config = {
                            restart: true,
                            parameters: {
                                skipSeconds: 0,
                                type: 2,
                                time: 300,
                                autohide: 0,
                                position: 0,
                                closePixel: '//ad2the.net/point/?method=retarget&&id=plc156777&seg=1&key=1ee794badae5a4d5edcafd0dc0155d76&adwuid=69875411067e812944873658',
                                newTab: true,
                                copyright: true,
                                timeout: 0,
                                additionalStyles: null,
                                secondsBeforeStart: 0
                            },
                            ads: [{
                                id: 14696,
                                link: '//bashirian.biz/content/static/78e69a3f728c2cd28c9af5db801651a5/14696.html?pauid=69875411067e812944873658&reqId=4e944e08-fc08-41fd-a071-4067e59bf3a1&external_domain=uafix.net&ct=4g',
                                image: '//s.schulist.link/media/6/6/66767917981964_31.webp'
                                , imageLandscape: '//s.schulist.link/media/7/7/77998665616810_649.webp' 
                            }]
                        };
                        window['mad_' + '14696'] = new AdMobileAd(config);
                    };
                    if (typeof AdMobileAd !== 'undefined') {
                        strt();
                    } else {
                        var head = document.querySelector('head');
                        var lb = document.createElement('script');
                        lb.src = '//ad2the.net/js/ma.js?1770475844';
                        lb.onload = strt;
                        head.appendChild(lb);
                    }
                })();window.amsp_load_0c3983ff=window.amsp_load_0c3983ff||[];window.amsp_load_0c3983ff.push({h:"78e69a3f728c2cd28c9af5db801651a5",ts:Date.now()});