/**
 * Timeplot
 * 
 * @fileOverview Timeplot
 * @name Timeplot
 */

Timeline.Debug = SimileAjax.Debug; // timeline uses it's own debug system which is not as advanced
var log = SimileAjax.Debug.log; // shorter name is easier to use

/*
 * This function is used to implement a raw but effective OOP-like inheritance
 * in various Timeplot classes.
 */
Object.extend = function(destination, source) {
    for (var property in source) {
        destination[property] = source[property];
    }
    return destination;
}

// ---------------------------------------------

/**
 * Create a timeplot attached to the given element and using the configuration from the given array of PlotInfos
 */
Timeplot.create = function(elmt, plotInfos) {
    return new Timeplot._Impl(elmt, plotInfos);
};

/**
 * Create a PlotInfo configuration from the given map of params
 */
Timeplot.createPlotInfo = function(params) {
    return {   
        id:                ("id" in params) ? params.id : "p" + Math.round(Math.random() * 1000000),
        dataSource:        ("dataSource" in params) ? params.dataSource : null,
        eventSource:       ("eventSource" in params) ? params.eventSource : null,
        timeGeometry:      ("timeGeometry" in params) ? params.timeGeometry : new Timeplot.DefaultTimeGeometry(),
        valueGeometry:     ("valueGeometry" in params) ? params.valueGeometry : new Timeplot.DefaultValueGeometry(),
        timeZone:          ("timeZone" in params) ? params.timeZone : 0,
        fillColor:         ("fillColor" in params) ? ((params.fillColor == "string") ? new Timeplot.Color(params.fillColor) : params.fillColor) : null,
        fillGradient:      ("fillGradient" in params) ? params.fillGradient : true,
        fillFrom:          ("fillFrom" in params) ? params.fillFrom : Number.NEGATIVE_INFINITY,
        lineColor:         ("lineColor" in params) ? ((params.lineColor == "string") ? new Timeplot.Color(params.lineColor) : params.lineColor) : new Timeplot.Color("#606060"),
        lineWidth:         ("lineWidth" in params) ? params.lineWidth : 1.0,
        dotRadius:         ("dotRadius" in params) ? params.dotRadius : 2.0,
        dotColor:          ("dotColor" in params) ? params.dotColor : null,
        eventLineWidth:    ("eventLineWidth" in params) ? params.eventLineWidth : 1.0,
        showValues:        ("showValues" in params) ? params.showValues : false,
        roundValues:       ("roundValues" in params) ? params.roundValues : true,
        valuesOpacity:     ("valuesOpacity" in params) ? params.valuesOpacity : 75,
        bubbleWidth:       ("bubbleWidth" in params) ? params.bubbleWidth : 300,
        bubbleHeight:      ("bubbleHeight" in params) ? params.bubbleHeight : 200
    };
};

// -------------------------------------------------------

/**
 * This is the implementation of the Timeplot object.
 *  
 * @constructor 
 */
Timeplot._Impl = function(elmt, plotInfos) {
	this._id = "t" + Math.round(Math.random() * 1000000);
    this._containerDiv = elmt;
    this._plotInfos = plotInfos;
    this._painters = {
        background: [],
        foreground: []
    };
    this._painter = null;
    this._active = false;
    this._upright = false;
    this._initialize();
};

Timeplot._Impl.prototype = {

    dispose: function() {
        for (var i = 0; i < this._plots.length; i++) {
            this._plots[i].dispose();
        }
        this._plots = null;
        this._plotsInfos = null;
        this._containerDiv.innerHTML = "";
    },
    
    /**
     * Returns the main container div this timeplot is operating on.
     */
    getElement: function() {
    	return this._containerDiv;
    },
    
    /**
     * Returns document this timeplot belongs to.
     */
    getDocument: function() {
        return this._containerDiv.ownerDocument;
    },

    /**
     * Append the given element to the timeplot DOM
     */
    add: function(div) {
        this._containerDiv.appendChild(div);
    },

    /**
     * Remove the given element to the timeplot DOM
     */
    remove: function(div) {
        this._containerDiv.removeChild(div);
    },

    /**
     * Add a painter to the timeplot
     */
    addPainter: function(layerName, painter) {
        var layer = this._painters[layerName];
        if (layer) {
            for (var i = 0; i < layer.length; i++) {
                if (layer[i].context._id == painter.context._id) {
                    return;
                }
            }
            layer.push(painter);
        }
    },
    
    /**
     * Remove a painter from the timeplot
     */
    removePainter: function(layerName, painter) {
        var layer = this._painters[layerName];
        if (layer) {
            for (var i = 0; i < layer.length; i++) {
                if (layer[i].context._id == painter.context._id) {
                    layer.splice(i, 1);
                    break;
                }
            }
        }
    },
    
    /**
     * Get the width in pixels of the area occupied by the entire timeplot in the page
     */
    getWidth: function() {
    	return this._containerDiv.clientWidth;
    },

    /**
     * Get the height in pixels of the area occupied by the entire timeplot in the page
     */
    getHeight: function() {
        return this._containerDiv.clientHeight;
    },
    
    /**
     * Get the drawing canvas associated with this timeplot
     */
    getCanvas: function() {
        return this._canvas;
    },
    
    /**
     * <p>Load the data from the given url into the given eventSource, using
     * the given separator to parse the columns and preprocess it before parsing
     * thru the optional filter function. The filter is useful for when 
     * the data is row-oriented but the format is not compatible with the
     * one that Timeplot expects.</p> 
     * 
     * <p>Here is an example of a filter that changes dates in the form 'yyyy/mm/dd'
     * in the required 'yyyy-mm-dd' format:
     * <pre>var dataFilter = function(data) {
     *     for (var i = 0; i < data.length; i++) {
     *         var row = data[i];
     *         row[0] = row[0].replace(/\//g,"-");
     *     }
     *     return data;
     * };</pre></p>
     */
    loadText: function(url, separator, eventSource, filter) {
    	if (this._active) {
	        var tp = this;
	        
	        var fError = function(statusText, status, xmlhttp) {
	            alert("Failed to load data xml from " + url + "\n" + statusText);
	            tp.hideLoadingMessage();
	        };
	        
	        var fDone = function(xmlhttp) {
	            try {
	                eventSource.loadText(xmlhttp.responseText, separator, url, filter);
	            } catch (e) {
	                SimileAjax.Debug.exception(e);
	            } finally {
	                tp.hideLoadingMessage();
	            }
	        };
	        
	        this.showLoadingMessage();
	        window.setTimeout(function() { SimileAjax.XmlHttp.get(url, fError, fDone); }, 0);
    	}
    },

    /**
     * Load event data from the given url into the given eventSource, using
     * the Timeline XML event format.
     */
    loadXML: function(url, eventSource) {
    	if (this._active) {
	        var tl = this;
	        
	        var fError = function(statusText, status, xmlhttp) {
	            alert("Failed to load data xml from " + url + "\n" + statusText);
	            tl.hideLoadingMessage();
	        };
	        
	        var fDone = function(xmlhttp) {
	            try {
	                var xml = xmlhttp.responseXML;
	                if (!xml.documentElement && xmlhttp.responseStream) {
	                    xml.load(xmlhttp.responseStream);
	                } 
	                eventSource.loadXML(xml, url);
	            } finally {
	                tl.hideLoadingMessage();
	            }
	        };
	        
	        this.showLoadingMessage();
	        window.setTimeout(function() { SimileAjax.XmlHttp.get(url, fError, fDone); }, 0);
    	}
    },
    
    /**
     * Overlay a 'div' element filled with the given text and styles to this timeplot
     * This is used to implement labels since canvas does not support drawing text.
     */
    putText: function(id, text, clazz, styles) {
        var div = this.putDiv(id, "timeplot-div " + clazz, styles);
        div.innerHTML = text;
        return div;
    },

    /**
     * Overlay a 'div' element, with the given class and the given styles to this timeplot.
     * This is used for labels and horizontal and vertical grids. 
     */
    putDiv: function(id, clazz, styles) {
    	var tid = this._id + "-" + id;
    	var div = document.getElementById(tid);
    	if (!div) {
	        var container = this._containerDiv.firstChild; // get the divs container
	        div = document.createElement("div");
	        div.setAttribute("id",tid);
	        container.appendChild(div);
    	}
        div.setAttribute("class","timeplot-div " + clazz);
        div.setAttribute("className","timeplot-div " + clazz);
        this.placeDiv(div,styles);
        return div;
    },
    
    /**
     * Associate the given map of styles to the given element. 
     * In case such styles indicate position (left,right,top,bottom) correct them
     * with the padding information so that they align to the 'internal' area
     * of the timeplot.
     */
    placeDiv: function(div, styles) {
        if (styles) {
            for (style in styles) {
                if (style == "left") {
                    styles[style] += this._paddingX;
                    styles[style] += "px";
                } else if (style == "right") {
                    styles[style] += this._paddingX;
                    styles[style] += "px";
                } else if (style == "top") {
                    styles[style] += this._paddingY;
                    styles[style] += "px";
                } else if (style == "bottom") {
                    styles[style] += this._paddingY;
                    styles[style] += "px";
                } else if (style == "width") {
                    if (styles[style] < 0) styles[style] = 0;
                    styles[style] += "px";
                } else if (style == "height") {
                    if (styles[style] < 0) styles[style] = 0;
                    styles[style] += "px";
                }
                div.style[style] = styles[style];
            }
        }
    },
    
    /**
     * return a {x,y} map with the location of the given element relative to the 'internal' area of the timeplot
     * (that is, without the container padding)
     */
    locate: function(div) {
    	return {
    		x: div.offsetLeft - this._paddingX,
    		y: div.offsetTop - this._paddingY
    	}
    },
    
    /**
     * Forces timeplot to re-evaluate the various value and time geometries
     * associated with its plot layers and repaint accordingly. This should
     * be invoked after the data in any of the data sources has been
     * modified.
     */
    update: function() {
    	if (this._active) {
	        for (var i = 0; i < this._plots.length; i++) {
	            var plot = this._plots[i];
	            var dataSource = plot.getDataSource();
	            if (dataSource) {
	                var range = dataSource.getRange();
	                if (range) {
	                	plot._valueGeometry.setRange(range);
	                	plot._timeGeometry.setRange(range);
	                }
	            }
	        }
	        this.paint();
    	}
    },
    
    /**
     * Forces timeplot to re-evaluate its own geometry, clear itself and paint.
     * This should be used instead of paint() when you're not sure if the 
     * geometry of the page has changed or not. 
     */
    repaint: function() {
    	if (this._active) {
	        this._prepareCanvas();
	        for (var i = 0; i < this._plots.length; i++) {
	            var plot = this._plots[i];
	            if (plot._timeGeometry) plot._timeGeometry.reset();
	            if (plot._valueGeometry) plot._valueGeometry.reset();
	        }
	        this.paint();
    	}
    },
    
    /**
     * Calls all the painters that were registered to this timeplot and makes them
     * paint the timeplot. This should be used only when you're sure that the geometry
     * of the page hasn't changed.
     * NOTE: painting is performed by a different thread and it's safe to call this
     * function in bursts (as in mousemove or during window resizing
     */
    paint: function() {
        if (this._active && this._painter == null) {
            var timeplot = this;
            this._painter = window.setTimeout(function() {
                timeplot._clearCanvas();
                
                var run = function(action,context) {
                    try {
                        if (context.setTimeplot) context.setTimeplot(timeplot);
                        action.apply(context,[]);
                    } catch (e) {
                        SimileAjax.Debug.exception(e);
                    }
                }
                
                var background = timeplot._painters.background;
                for (var i = 0; i < background.length; i++) {
                    run(background[i].action, background[i].context); 
                }
                var foreground = timeplot._painters.foreground;
                for (var i = 0; i < foreground.length; i++) {
                    run(foreground[i].action, foreground[i].context); 
                }
                
                timeplot._painter = null;
            }, 20);
        }
    },

    _clearCanvas: function() {
    	var canvas = this.getCanvas();
    	var ctx = canvas.getContext('2d');
        ctx.clearRect(0,0,canvas.width,canvas.height);
    },
    
    _prepareCanvas: function() {
        var canvas = this.getCanvas();

        // using jQuery.  note we calculate the average padding; if your
        // padding settings are not symmetrical, the labels will be off
        // since they expect to be centered on the canvas.
        var con = $('#' + this._containerDiv.id);
        this._paddingX = (parseInt(con.css('paddingLeft')) +
                          parseInt(con.css('paddingRight'))) / 2;
        this._paddingY = (parseInt(con.css('paddingTop')) +
                          parseInt(con.css('paddingBottom'))) / 2;

        canvas.width = this.getWidth() - (this._paddingX * 2);
        canvas.height = this.getHeight() - (this._paddingY * 2);

        var ctx = canvas.getContext('2d');
        this._setUpright(ctx, canvas);
        ctx.globalCompositeOperation = 'source-over';
    },

    _setUpright: function(ctx, canvas) {
        // excanvas+IE requires this to be done only once, ever; actual canvas
        // implementations reset and require this for each call to re-layout
        if (!SimileAjax.Platform.browser.isIE) this._upright = false;
        if (!this._upright) {
            this._upright = true;
            ctx.translate(0, canvas.height);
            ctx.scale(1,-1);
        }
    },
    
    _isBrowserSupported: function(canvas) {
    	var browser = SimileAjax.Platform.browser;
    	if ((canvas.getContext && window.getComputedStyle) ||
            (browser.isIE && browser.majorVersion >= 6)) {
        	return true;
    	} else {
    		return false;
    	}
    },
    
    _initialize: function() {
    	
    	// initialize the window manager (used to handle the popups)
    	// NOTE: this is a singleton and it's safe to call multiple times
    	SimileAjax.WindowManager.initialize(); 
    	
        var containerDiv = this._containerDiv;
        var doc = containerDiv.ownerDocument;
    
        // make sure the timeplot div has the right class    
        containerDiv.className = "timeplot-container " + containerDiv.className;
            
        // clean it up if it contains some content
        while (containerDiv.firstChild) {
            containerDiv.removeChild(containerDiv.firstChild);
        }
        
        var canvas = doc.createElement("canvas");
        
        if (this._isBrowserSupported(canvas)) {
            // this is where we'll place the labels
            var labels = doc.createElement("div");
            containerDiv.appendChild(labels);

            this._canvas = canvas;
            canvas.className = "timeplot-canvas";
            containerDiv.appendChild(canvas);
            if(!canvas.getContext && G_vmlCanvasManager) {
                canvas = G_vmlCanvasManager.initElement(this._canvas);
                this._canvas = canvas;
            }
            this._prepareCanvas();
    
            // inserting copyright and link to simile
            var elmtCopyright = SimileAjax.Graphics.createTranslucentImage(Timeplot.urlPrefix + "images/copyright.png");
            elmtCopyright.className = "timeplot-copyright";
            elmtCopyright.title = "Timeplot (c) SIMILE - http://simile.mit.edu/timeplot/";
            SimileAjax.DOM.registerEvent(elmtCopyright, "click", function() { window.location = "http://simile.mit.edu/timeplot/"; });
            containerDiv.appendChild(elmtCopyright);
            
            var timeplot = this;
            var painter = {
                onAddMany: function() { timeplot.update(); },
                onClear:   function() { timeplot.update(); }
            }

            // creating painters
            this._plots = [];
            if (this._plotInfos) {
                for (var i = 0; i < this._plotInfos.length; i++) {
                    var plot = new Timeplot.Plot(this, this._plotInfos[i]);
                    var dataSource = plot.getDataSource();
                    if (dataSource) {
                        dataSource.addListener(painter);
                    }
                    this.addPainter("background", {
                        context: plot.getTimeGeometry(),
                        action: plot.getTimeGeometry().paint
                    });
                    this.addPainter("background", {
                        context: plot.getValueGeometry(),
                        action: plot.getValueGeometry().paint
                    });
                    this.addPainter("foreground", {
                        context: plot,
                        action: plot.paint
                    });
                    this._plots.push(plot);
                    plot.initialize();
                }
            }
                
            // creating loading UI
            var message = SimileAjax.Graphics.createMessageBubble(doc);
            message.containerDiv.className = "timeplot-message-container";
            containerDiv.appendChild(message.containerDiv);
            
            message.contentDiv.className = "timeplot-message";
            message.contentDiv.innerHTML = "<img src='" + Timeplot.urlPrefix + "images/progress-running.gif' /> Loading...";
            
            this.showLoadingMessage = function() { message.containerDiv.style.display = "block"; };
            this.hideLoadingMessage = function() { message.containerDiv.style.display = "none"; };
    
            this._active = true;
            
        } else {
    
            this._message = SimileAjax.Graphics.createMessageBubble(doc);
            this._message.containerDiv.className = "timeplot-message-container";
            this._message.containerDiv.style.top = "15%";
            this._message.containerDiv.style.left = "20%";
            this._message.containerDiv.style.right = "20%";
            this._message.containerDiv.style.minWidth = "20em";
            this._message.contentDiv.className = "timeplot-message";
            this._message.contentDiv.innerHTML = "We're terribly sorry, but your browser is not currently supported by <a href='http://simile.mit.edu/timeplot/'>Timeplot</a>.<br><br> We are working on supporting it in the near future but, for now, see the <a href='http://simile.mit.edu/wiki/Timeplot_Limitations'>list of currently supported browsers</a>.";
            this._message.containerDiv.style.display = "block";

            containerDiv.appendChild(this._message.containerDiv);
    
        }
    }
};
