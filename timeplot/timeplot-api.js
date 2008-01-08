/*==================================================
 *  Simile Timeplot API
 *
 *  Include Timeplot in your HTML file as follows:
 *    <script src="http://static.simile.mit.edu/timeplot/api/1.0/timeplot-api.js" type="text/javascript"></script>
 *
 *==================================================*/

(function() {

    var local = false;

    // obtain local mode from the document URL    
    if (document.location.search.length > 0) {
        var params = document.location.search.substr(1).split("&");
        for (var i = 0; i < params.length; i++) {
            if (params[i] == "local") {
                local = true;
            }
        }
    }

    // obtain local mode from the script URL params attribute
    if (!local) {
        var heads = document.documentElement.getElementsByTagName("head");
        for (var h = 0; h < heads.length; h++) {
            var node = heads[h].firstChild;
            while (node != null) {
                if (node.nodeType == 1 && node.tagName.toLowerCase() == "script") {
                    var url = node.src;
                    if (url.indexOf("timeplot-api") >= 0) {
                        local = (url.indexOf("local") >= 0);
                    }
                }
                node = node.nextSibling;
            }
        }
    }

    // Load Timeplot if it's not already loaded (after SimileAjax and Timeline)
    var loadTimeplot = function() {

        if (typeof window.Timeplot != "undefined") {
            return;
        }
        
        window.Timeplot = {
            loaded:     false,
            params:     { bundle: true, autoCreate: true },
            namespace:  "http://simile.mit.edu/2007/06/timeplot#",
            importers:  {}
        };
    
        var javascriptFiles = [
            "timeplot.js",
            "plot.js",
            "sources.js",
            "geometry.js",
            "color.js",
            "math.js",
            "processor.js"
        ];
        var cssFiles = [
            "timeplot.css"
        ];
        
        var locales = [ "en" ];

        var defaultClientLocales = ("language" in navigator ? navigator.language : navigator.browserLanguage).split(";");
        for (var l = 0; l < defaultClientLocales.length; l++) {
            var locale = defaultClientLocales[l];
            if (locale != "en") {
                var segments = locale.split("-");
                if (segments.length > 1 && segments[0] != "en") {
                    locales.push(segments[0]);
                }
                locales.push(locale);
            }
        }

        var paramTypes = { bundle:Boolean, js:Array, css:Array, autoCreate:Boolean };
        if (typeof Timeplot_urlPrefix == "string") {
            Timeplot.urlPrefix = Timeplot_urlPrefix;
            if ("Timeplot_parameters" in window) {
                SimileAjax.parseURLParameters(Timeplot_parameters, Timeplot.params, paramTypes);
            }
        } else {
            var url = SimileAjax.findScript(document, "/timeplot-api.js");
            if (url == null) {
                Timeplot.error = new Error("Failed to derive URL prefix for Simile Timeplot API code files");
                return;
            }
            Timeplot.urlPrefix = url.substr(0, url.indexOf("timeplot-api.js"));
        
            SimileAjax.parseURLParameters(url, Timeplot.params, paramTypes);
        }

        if (Timeplot.params.locale) { // ISO-639 language codes,
            // optional ISO-3166 country codes (2 characters)
            if (Timeplot.params.locale != "en") {
                var segments = Timeplot.params.locale.split("-");
                if (segments.length > 1 && segments[0] != "en") {
                    locales.push(segments[0]);
                }
                locales.push(Timeplot.params.locale);
            }
        }

        var timeplotURLPrefix = (local) ? "/timeplot/api/1.0/" : Timeplot.urlPrefix;

        if (local && !("console" in window)) {
            var firebug = [ timeplotURLPrefix + "lib/firebug/firebug.js" ];
            SimileAjax.includeJavascriptFiles(document, "", firebug);
        }
        
        var canvas = document.createElement("canvas");

        if (!canvas.getContext) {
            var excanvas = [ timeplotURLPrefix + "lib/excanvas.js" ];
            SimileAjax.includeJavascriptFiles(document, "", excanvas);
        }
        
        var scriptURLs = Timeplot.params.js || [];
        var cssURLs = Timeplot.params.css || [];

        // Core scripts and styles
        if (Timeplot.params.bundle && !local) {
            scriptURLs.push(timeplotURLPrefix + "timeplot-bundle.js");
            cssURLs.push(timeplotURLPrefix + "timeplot-bundle.css");
        } else {
            SimileAjax.prefixURLs(scriptURLs, timeplotURLPrefix + "scripts/", javascriptFiles);
            SimileAjax.prefixURLs(cssURLs, timeplotURLPrefix + "styles/", cssFiles);
        }
        
        // Localization
        //for (var i = 0; i < locales.length; i++) {
        //    scriptURLs.push(Timeplot.urlPrefix + "locales/" + locales[i] + "/locale.js");
        //};
        
        window.SimileAjax_onLoad = function() {
            if (local && window.console.open) window.console.open();
            if (Timeplot.params.callback) {
                eval(Timeplot.params.callback + "()");
            }
        }
        
        SimileAjax.includeJavascriptFiles(document, "", scriptURLs);
        SimileAjax.includeCssFiles(document, "", cssURLs);
        Timeplot.loaded = true;
    };

    // Load Timeline if it's not already loaded (after SimileAjax and before Timeplot)
    var loadTimeline = function() {
        if (typeof Timeline != "undefined") {
            loadTimeplot();
        } else {
            var timelineURL = (local) ? "/timeline/api-2.0/timeline-api.js?bundle=false" : "http://static.simile.mit.edu/timeline/api-2.0/timeline-api.js";
            window.SimileAjax_onLoad = loadTimeplot;
            SimileAjax.includeJavascriptFile(document, timelineURL);
        }
    };
    
    // Load SimileAjax if it's not already loaded
    if (typeof SimileAjax == "undefined") {
        window.SimileAjax_onLoad = loadTimeline;
        
        var url = local ?
            "/ajax/api-2.0/simile-ajax-api.js?bundle=false" :
            "http://static.simile.mit.edu/ajax/api-2.0/simile-ajax-api.js?bundle=true";
                
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
        loadTimeline();
    }
})();
