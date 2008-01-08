/*==================================================
 *  Timeline API
 *
 *  This file will load all the Javascript files
 *  necessary to make the standard timeline work.
 *  It also detects the default locale.
 *
 *  Include this file in your HTML file as follows:
 *
 *    <script src="http://simile.mit.edu/timeline/api/scripts/timeline-api.js" type="text/javascript"></script>
 *
 *==================================================
 */

(function() {
    var useLocalResources = false;
    if (document.location.search.length > 0) {
        var params = document.location.search.substr(1).split("&");
        for (var i = 0; i < params.length; i++) {
            if (params[i] == "timeline-use-local-resources") {
                useLocalResources = true;
            }
        }
    };
    
    var loadMe = function() {
        if ("Timeline" in window) {
            return;
        }
        
        window.Timeline = new Object();
        window.Timeline.DateTime = window.SimileAjax.DateTime; // for backward compatibility
    
        var bundle = true;
        var javascriptFiles = [
            "timeline.js",
            "themes.js",
            "ethers.js",
            "ether-painters.js",
            "labellers.js",
            "sources.js",
            "original-painter.js",
            "detailed-painter.js",
            "overview-painter.js",
            "decorators.js",
            "units.js"
        ];
        var cssFiles = [
            "timeline.css",
            "ethers.css",
            "events.css"
        ];
        
        var localizedJavascriptFiles = [
            "timeline.js",
            "labellers.js"
        ];
        var localizedCssFiles = [
        ];
        
        // ISO-639 language codes, ISO-3166 country codes (2 characters)
        var supportedLocales = [
            "cs",       // Czech
            "de",       // German
            "en",       // English
            "es",       // Spanish
            "fr",       // French
            "it",       // Italian
            "ru",       // Russian
            "se",       // Swedish
            "tr",       // Turkish
            "vi",       // Vietnamese
            "zh"        // Chinese
        ];
        
        try {
            var desiredLocales = [ "en" ];
            var defaultServerLocale = "en";
            
            var parseURLParameters = function(parameters) {
                var params = parameters.split("&");
                for (var p = 0; p < params.length; p++) {
                    var pair = params[p].split("=");
                    if (pair[0] == "locales") {
                        desiredLocales = desiredLocales.concat(pair[1].split(","));
                    } else if (pair[0] == "defaultLocale") {
                        defaultServerLocale = pair[1];
                    } else if (pair[0] == "bundle") {
                        bundle = pair[1] != "false";
                    }
                }
            };
            
            (function() {
                if (typeof Timeline_urlPrefix == "string") {
                    Timeline.urlPrefix = Timeline_urlPrefix;
                    if (typeof Timeline_parameters == "string") {
                        parseURLParameters(Timeline_parameters);
                    }
                } else {
                    var heads = document.documentElement.getElementsByTagName("head");
                    for (var h = 0; h < heads.length; h++) {
                        var scripts = heads[h].getElementsByTagName("script");
                        for (var s = 0; s < scripts.length; s++) {
                            var url = scripts[s].src;
                            var i = url.indexOf("timeline-api.js");
                            if (i >= 0) {
                                Timeline.urlPrefix = url.substr(0, i);
                                var q = url.indexOf("?");
                                if (q > 0) {
                                    parseURLParameters(url.substr(q + 1));
                                }
                                return;
                            }
                        }
                    }
                    throw new Error("Failed to derive URL prefix for Timeline API code files");
                }
            })();
            
            var includeJavascriptFiles = function(urlPrefix, filenames) {
                SimileAjax.includeJavascriptFiles(document, urlPrefix, filenames);
            }
            var includeCssFiles = function(urlPrefix, filenames) {
                SimileAjax.includeCssFiles(document, urlPrefix, filenames);
            }
            
            /*
             *  Include non-localized files
             */
            if (bundle) {
                includeJavascriptFiles(Timeline.urlPrefix, [ "timeline-bundle.js" ]);
                includeCssFiles(Timeline.urlPrefix, [ "timeline-bundle.css" ]);
            } else {
                includeJavascriptFiles(Timeline.urlPrefix + "scripts/", javascriptFiles);
                includeCssFiles(Timeline.urlPrefix + "styles/", cssFiles);
            }
            
            /*
             *  Include localized files
             */
            var loadLocale = [];
            loadLocale[defaultServerLocale] = true;
            
            var tryExactLocale = function(locale) {
                for (var l = 0; l < supportedLocales.length; l++) {
                    if (locale == supportedLocales[l]) {
                        loadLocale[locale] = true;
                        return true;
                    }
                }
                return false;
            }
            var tryLocale = function(locale) {
                if (tryExactLocale(locale)) {
                    return locale;
                }
                
                var dash = locale.indexOf("-");
                if (dash > 0 && tryExactLocale(locale.substr(0, dash))) {
                    return locale.substr(0, dash);
                }
                
                return null;
            }
            
            for (var l = 0; l < desiredLocales.length; l++) {
                tryLocale(desiredLocales[l]);
            }
            
            var defaultClientLocale = defaultServerLocale;
            var defaultClientLocales = ("language" in navigator ? navigator.language : navigator.browserLanguage).split(";");
            for (var l = 0; l < defaultClientLocales.length; l++) {
                var locale = tryLocale(defaultClientLocales[l]);
                if (locale != null) {
                    defaultClientLocale = locale;
                    break;
                }
            }
            
            for (var l = 0; l < supportedLocales.length; l++) {
                var locale = supportedLocales[l];
                if (loadLocale[locale]) {
                    includeJavascriptFiles(Timeline.urlPrefix + "scripts/l10n/" + locale + "/", localizedJavascriptFiles);
                    includeCssFiles(Timeline.urlPrefix + "styles/l10n/" + locale + "/", localizedCssFiles);
                }
            }
            
            Timeline.serverLocale = defaultServerLocale;
            Timeline.clientLocale = defaultClientLocale;
        } catch (e) {
            alert(e);
        }
    };
    
    /*
     *  Load SimileAjax if it's not already loaded
     */
    if (typeof SimileAjax == "undefined") {
        window.SimileAjax_onLoad = loadMe;
        
        var url = useLocalResources ?
            "http://127.0.0.1:9999/ajax/api/simile-ajax-api.js?bundle=false" :
            "http://static.simile.mit.edu/ajax/api-2.0/simile-ajax-api.js";
        var createScriptElement = function() {
            var script = document.createElement("script");
            script.type = "text/javascript";
            script.language = "JavaScript";
            script.src = url;
            document.getElementsByTagName("head")[0].appendChild(script);
        }
        if (document.body == null) {
            try {
                document.write("<script src='" + url + "' type='text/javascript'></script>");
            } catch (e) {
                createScriptElement();
            }
        } else {
            createScriptElement();
        }
    } else {
        loadMe();
    }
})();
