/**
 * Geometries
 * 
 * @fileOverview Geometries
 * @name Geometries
 */

/**
 * This is the constructor for the default value geometry.
 * A value geometry is what regulates mapping of the plot values to the screen y coordinate.
 * If two plots share the same value geometry, they will be drawn using the same scale.
 * If "min" and "max" parameters are not set, the geometry will stretch itself automatically
 * so that the entire plot will be drawn without overflowing. The stretching happens also
 * when a geometry is shared between multiple plots, the one with the biggest range will
 * win over the others.
 * 
 * @constructor
 */
Timeplot.DefaultValueGeometry = function(params) {
    if (!params) params = {};
    this._id = ("id" in params) ? params.id : "g" + Math.round(Math.random() * 1000000);
    this._axisColor = ("axisColor" in params) ? ((typeof params.axisColor == "string") ? new Timeplot.Color(params.axisColor) : params.axisColor) : new Timeplot.Color("#606060"),
    this._gridColor = ("gridColor" in params) ? ((typeof params.gridColor == "string") ? new Timeplot.Color(params.gridColor) : params.gridColor) : null,
    this._gridLineWidth = ("gridLineWidth" in params) ? params.gridLineWidth : 0.5;
    this._axisLabelsPlacement = ("axisLabelsPlacement" in params) ? params.axisLabelsPlacement : "right";
    this._gridSpacing = ("gridSpacing" in params) ? params.gridStep : 50;
    this._gridType = ("gridType" in params) ? params.gridType : "short";
    this._gridShortSize = ("gridShortSize" in params) ? params.gridShortSize : 10;
    this._minValue = ("min" in params) ? params.min : null;
    this._maxValue = ("max" in params) ? params.max : null;
    this._linMap = {
        direct: function(v) {
            return v;
        },
        inverse: function(y) {
            return y;
        }
    }
    this._map = this._linMap;
    this._labels = [];
    this._grid = [];
}

Timeplot.DefaultValueGeometry.prototype = {

    /**
     * Since geometries can be reused across timeplots, we need to call this function
     * before we can paint using this geometry.
     */
    setTimeplot: function(timeplot) {
        this._timeplot = timeplot;
        this._canvas = timeplot.getCanvas();
        this.reset();
    },

    /**
     * Called by all the plot layers this geometry is associated with
     * to update the value range. Unless min/max values are specified
     * in the parameters, the biggest value range will be used.
     */
    setRange: function(range) {
        if ((this._minValue == null) || ((this._minValue != null) && (range.min < this._minValue))) {
            this._minValue = range.min;
        }
        if ((this._maxValue == null) || ((this._maxValue != null) && (range.max * 1.05 > this._maxValue))) {
            this._maxValue = range.max * 1.05; // get a little more head room to avoid hitting the ceiling
        }

        this._updateMappedValues();

        if (!(this._minValue == 0 && this._maxValue == 0)) {
            this._grid = this._calculateGrid();
        }
    },

    /**
     * Called after changing ranges or canvas size to reset the grid values
     */
    reset: function() {
    	this._clearLabels();
        this._updateMappedValues();
        this._grid = this._calculateGrid();
    },

    /**
     * Map the given value to a y screen coordinate.
     */
    toScreen: function(value) {
    	if (this._canvas && this._maxValue) {
	        var v = value - this._minValue;
	        return this._canvas.height * (this._map.direct(v)) / this._mappedRange;
    	} else {
    		return -50;
    	}
    },

    /**
     * Map the given y screen coordinate to a value
     */
    fromScreen: function(y) {
    	if (this._canvas) {
            return this._map.inverse(this._mappedRange * y / this._canvas.height) + this._minValue;
    	} else {
    		return 0;
    	}
    },

    /**
     * Each geometry is also a painter and paints the value grid and grid labels.
     */
    paint: function() {
    	if (this._timeplot) {
	        var ctx = this._canvas.getContext('2d');
	
	        ctx.lineJoin = 'miter';
	
            // paint grid
            if (this._gridColor) {        
                var gridGradient = ctx.createLinearGradient(0,0,0,this._canvas.height);
                gridGradient.addColorStop(0, this._gridColor.toHexString());
		        gridGradient.addColorStop(0.3, this._gridColor.toHexString());
		        gridGradient.addColorStop(1, "rgba(255,255,255,0.5)");

                ctx.lineWidth = this._gridLineWidth;
                ctx.strokeStyle = gridGradient;
    
                for (var i = 0; i < this._grid.length; i++) {
                    var tick = this._grid[i];
                    var y = Math.floor(tick.y) + 0.5;
                    if (typeof tick.label != "undefined") {
	                    if (this._axisLabelsPlacement == "left") {
	                        var div = this._timeplot.putText(this._id + "-" + i, tick.label,"timeplot-grid-label",{
	                            left: 4,
	                            bottom: y + 2,
	                            color: this._gridColor.toHexString(),
	                            visibility: "hidden"
	                        });
	                    } else if (this._axisLabelsPlacement == "right") {
	                        var div = this._timeplot.putText(this._id + "-" + i, tick.label, "timeplot-grid-label",{
	                            right: 4,
	                            bottom: y + 2,
	                            color: this._gridColor.toHexString(),
	                            visibility: "hidden"
	                        });
	                    }
	                    if (y + div.clientHeight < this._canvas.height + 10) {
	                        div.style.visibility = "visible"; // avoid the labels that would overflow
	                    }
                    }

                    // draw grid
                    ctx.beginPath();
                    if (this._gridType == "long" || tick.label == 0) {
	                    ctx.moveTo(0, y);
	                    ctx.lineTo(this._canvas.width, y);
                    } else if (this._gridType == "short") {
                        if (this._axisLabelsPlacement == "left") {
	                        ctx.moveTo(0, y);
	                        ctx.lineTo(this._gridShortSize, y);
                        } else if (this._axisLabelsPlacement == "right") {
	                        ctx.moveTo(this._canvas.width, y);
	                        ctx.lineTo(this._canvas.width - this._gridShortSize, y);
                        }                    	
                    }
                    ctx.stroke();
                }
            }
		
	        // paint axis
            var axisGradient = ctx.createLinearGradient(0,0,0,this._canvas.height);
            axisGradient.addColorStop(0, this._axisColor.toString());
            axisGradient.addColorStop(0.5, this._axisColor.toString());
            axisGradient.addColorStop(1, "rgba(255,255,255,0.5)");
	        
	        ctx.lineWidth = 1;
            ctx.strokeStyle = axisGradient;
	
	        // left axis
	        ctx.beginPath();
	        ctx.moveTo(0,this._canvas.height);
	        ctx.lineTo(0,0);
	        ctx.stroke();
	        
	        // right axis
	        ctx.beginPath();
	        ctx.moveTo(this._canvas.width,0);
	        ctx.lineTo(this._canvas.width,this._canvas.height);
	        ctx.stroke();
    	}
    },
    
    /**
     * Removes all the labels that were added by this geometry
     */
    _clearLabels: function() {
    	for (var i = 0; i < this._labels.length; i++) {
    		var l = this._labels[i];
    		var parent = l.parentNode;
    		if (parent) parent.removeChild(l);
    	}
    },
    
    /*
     * This function calculates the grid spacing that it will be used 
     * by this geometry to draw the grid in order to reduce clutter. 
     */
    _calculateGrid: function() {
        var grid = [];
        
        if (!this._canvas || this._valueRange == 0) return grid;
                
        var power = 0;
    	if (this._valueRange > 1) {
    		while (Math.pow(10,power) < this._valueRange) {
    			power++;
    		}
    		power--;
    	} else {
            while (Math.pow(10,power) > this._valueRange) {
                power--;
            }
    	}

        var unit = Math.pow(10,power);
        var inc = unit;
        while (true) {
            var dy = this.toScreen(this._minValue + inc);

	        while (dy < this._gridSpacing) {
	        	inc += unit;
                dy = this.toScreen(this._minValue + inc);
	        }

	        if (dy > 2 * this._gridSpacing) { // grids are too spaced out
	        	unit /= 10;
	        	inc = unit;
	        } else {
	        	break;
	        }
        }
        
        var v = 0;
        var y = this.toScreen(v);
        if (this._minValue >= 0) {
        	while (y < this._canvas.height) {
        		if (y > 0) {
        			grid.push({ y: y, label: v });
        		}
        		v += inc;
        		y = this.toScreen(v);
        	}
        } else if (this._maxValue <= 0) {
            while (y > 0) {
                if (y < this._canvas.height) {
                    grid.push({ y: y, label: v });
                }
                v -= inc;
                y = this.toScreen(v);
            }
        } else {
            while (y < this._canvas.height) {
                if (y > 0) {
                    grid.push({ y: y, label: v });
                }
                v += inc;
                y = this.toScreen(v);
            }
            v = -inc;
            y = this.toScreen(v);
            while (y > 0) {
                if (y < this._canvas.height) {
                    grid.push({ y: y, label: v });
                }
                v -= inc;
                y = this.toScreen(v);
            }
        }
        
        return grid;
    },

    /*
     * Update the values that are used by the paint function so that
     * we don't have to calculate them at every repaint.
     */
    _updateMappedValues: function() {
        this._valueRange = Math.abs(this._maxValue - this._minValue);
        this._mappedRange = this._map.direct(this._valueRange);
    }
    
}

// --------------------------------------------------

/**
 * This is the constructor for a Logarithmic value geometry, which
 * is useful when plots have values in different magnitudes but 
 * exhibit similar trends and such trends want to be shown on the same
 * plot (here a cartesian geometry would make the small magnitudes 
 * disappear).
 * 
 * NOTE: this class extends Timeplot.DefaultValueGeometry and inherits
 * all of the methods of that class. So refer to that class. 
 * 
 * @constructor
 */
Timeplot.LogarithmicValueGeometry = function(params) {
    Timeplot.DefaultValueGeometry.apply(this, arguments);
    this._logMap = {
    	direct: function(v) {
			return Math.log(v + 1) / Math.log(10);
    	},
    	inverse: function(y) {
			return Math.exp(Math.log(10) * y) - 1;
    	}
    }
    this._mode = "log";
    this._map = this._logMap;
    this._calculateGrid = this._logarithmicCalculateGrid;
};

Timeplot.LogarithmicValueGeometry.prototype._linearCalculateGrid = Timeplot.DefaultValueGeometry.prototype._calculateGrid;

Object.extend(Timeplot.LogarithmicValueGeometry.prototype,Timeplot.DefaultValueGeometry.prototype);

/*
 * This function calculates the grid spacing that it will be used 
 * by this geometry to draw the grid in order to reduce clutter. 
 */
Timeplot.LogarithmicValueGeometry.prototype._logarithmicCalculateGrid = function() {
    var grid = [];
    
    if (!this._canvas || this._valueRange == 0) return grid;

    var v = 1;
    var y = this.toScreen(v);
    while (y < this._canvas.height || isNaN(y)) {
        if (y > 0) {
            grid.push({ y: y, label: v });
        }
        v *= 10;
        y = this.toScreen(v);
    }
    
    return grid;
};

/**
 * Turn the logarithmic scaling off. 
 */
Timeplot.LogarithmicValueGeometry.prototype.actLinear = function() {
    this._mode = "lin";
    this._map = this._linMap;
    this._calculateGrid = this._linearCalculateGrid;
	this.reset();
}

/**
 * Turn the logarithmic scaling on. 
 */
Timeplot.LogarithmicValueGeometry.prototype.actLogarithmic = function() {
    this._mode = "log";
    this._map = this._logMap;
    this._calculateGrid = this._logarithmicCalculateGrid;
    this.reset();
}

/**
 * Toggle logarithmic scaling seeting it to on if off and viceversa. 
 */
Timeplot.LogarithmicValueGeometry.prototype.toggle = function() {
	if (this._mode == "log") {
		this.actLinear();
	} else {
        this.actLogarithmic();
	}
}

// -----------------------------------------------------

/**
 * This is the constructor for the default time geometry.
 * 
 * @constructor
 */
Timeplot.DefaultTimeGeometry = function(params) {
    if (!params) params = {};
    this._id = ("id" in params) ? params.id : "g" + Math.round(Math.random() * 1000000);
    this._locale = ("locale" in params) ? params.locale : "en";
    this._timeZone = ("timeZone" in params) ? params.timeZone : SimileAjax.DateTime.getTimezone();
    this._labeller = ("labeller" in params) ? params.labeller : null;
    this._axisColor = ("axisColor" in params) ? ((params.axisColor == "string") ? new Timeplot.Color(params.axisColor) : params.axisColor) : new Timeplot.Color("#606060"),
    this._gridColor = ("gridColor" in params) ? ((params.gridColor == "string") ? new Timeplot.Color(params.gridColor) : params.gridColor) : null,
    this._gridLineWidth = ("gridLineWidth" in params) ? params.gridLineWidth : 0.5;
    this._axisLabelsPlacement = ("axisLabelsPlacement" in params) ? params.axisLabelsPlacement : "bottom";
    this._gridStep = ("gridStep" in params) ? params.gridStep : 100;
    this._gridStepRange = ("gridStepRange" in params) ? params.gridStepRange : 20;
    this._min = ("min" in params) ? params.min : null;
    this._max = ("max" in params) ? params.max : null;
    this._timeValuePosition =("timeValuePosition" in params) ? params.timeValuePosition : "bottom";
    this._unit = ("unit" in params) ? params.unit : Timeline.NativeDateUnit;
    this._linMap = {
        direct: function(t) {
            return t;
        },
        inverse: function(x) {
            return x;
        }
    }
    this._map = this._linMap;
    this._labeler = this._unit.createLabeller(this._locale, this._timeZone);
    var dateParser = this._unit.getParser("iso8601");
    if (this._min && !this._min.getTime) {
        this._min = dateParser(this._min);
    }
    if (this._max && !this._max.getTime) {
        this._max = dateParser(this._max);
    }
    this._grid = [];
}

Timeplot.DefaultTimeGeometry.prototype = {

    /**
     * Since geometries can be reused across timeplots, we need to call this function
     * before we can paint using this geometry.
     */
    setTimeplot: function(timeplot) {
    	this._timeplot = timeplot;
    	this._canvas = timeplot.getCanvas();
        this.reset();
    },

    /**
     * Called by all the plot layers this geometry is associated with
     * to update the time range. Unless min/max values are specified
     * in the parameters, the biggest range will be used.
     */
    setRange: function(range) {
    	if (this._min) {
    		this._earliestDate = this._min;
    	} else if (range.earliestDate && ((this._earliestDate == null) || ((this._earliestDate != null) && (range.earliestDate.getTime() < this._earliestDate.getTime())))) {
            this._earliestDate = range.earliestDate;
        }
        
        if (this._max) {
        	this._latestDate = this._max;
        } else if (range.latestDate && ((this._latestDate == null) || ((this._latestDate != null) && (range.latestDate.getTime() > this._latestDate.getTime())))) {
            this._latestDate = range.latestDate;
        }

        if (!this._earliestDate && !this._latestDate) {
            this._grid = [];
        } else {
        	this.reset(); 
        }
    },
    
    /**
     * Called after changing ranges or canvas size to reset the grid values
     */
    reset: function() {
        this._updateMappedValues();
        if (this._canvas) this._grid = this._calculateGrid();
    },
    
    /**
     * Map the given date to a x screen coordinate.
     */
    toScreen: function(time) {
    	if (this._canvas && this._latestDate) {
            var t = time - this._earliestDate.getTime();
            return this._canvas.width * this._map.direct(t) / this._mappedPeriod;
        } else {
            return -50;
        } 
    },

    /**
     * Map the given x screen coordinate to a date.
     */
    fromScreen: function(x) {
    	if (this._canvas) {
            return this._map.inverse(this._mappedPeriod * x / this._canvas.width) + this._earliestDate.getTime();
    	} else {
    		return 0;
    	} 
    },
    
    /**
     * Get a period (in milliseconds) this time geometry spans.
     */
    getPeriod: function() {
    	return this._period;
    },
    
    /**
     * Return the labeler that has been associated with this time geometry
     */
    getLabeler: function() {
    	return this._labeler;
    },

    /**
     * Return the time unit associated with this time geometry
     */
    getUnit: function() {
        return this._unit;
    },

   /**
    * Each geometry is also a painter and paints the value grid and grid labels.
    */
    paint: function() {
    	if (this._canvas) {
	    	var unit = this._unit;
	        var ctx = this._canvas.getContext('2d');
	
	        var gradient = ctx.createLinearGradient(0,0,0,this._canvas.height);
	
	        ctx.strokeStyle = gradient;
	        ctx.lineWidth = this._gridLineWidth;
	        ctx.lineJoin = 'miter';
	
	        // paint grid
	        if (this._gridColor) {        
	            gradient.addColorStop(0, this._gridColor.toString());
	            gradient.addColorStop(1, "rgba(255,255,255,0.9)");
	
	            for (var i = 0; i < this._grid.length; i++) {
	            	var tick = this._grid[i];
	            	var x = Math.floor(tick.x) + 0.5;
                    if (this._axisLabelsPlacement == "top") {
                        var div = this._timeplot.putText(this._id + "-" + i, tick.label,"timeplot-grid-label",{
                            left: x + 4,
                            top: 2,
                            visibility: "hidden"
                        });
                    } else if (this._axisLabelsPlacement == "bottom") {
                        var div = this._timeplot.putText(this._id + "-" + i, tick.label, "timeplot-grid-label",{
                            left: x + 4,
                            bottom: 2,
                            visibility: "hidden"
                        });
                    }
                    if (x + div.clientWidth < this._canvas.width + 10) {
                        div.style.visibility = "visible"; // avoid the labels that would overflow
                    }

                    // draw separator
                    ctx.beginPath();
                    ctx.moveTo(x,0);
                    ctx.lineTo(x,this._canvas.height);
                    ctx.stroke();
	            }
	        }
	
	        // paint axis
	        gradient.addColorStop(0, this._axisColor.toString());
	        gradient.addColorStop(1, "rgba(255,255,255,0.5)");
	        
	        ctx.lineWidth = 1;
	        gradient.addColorStop(0, this._axisColor.toString());
	
	        ctx.beginPath();
	        ctx.moveTo(0,0);
	        ctx.lineTo(this._canvas.width,0);
	        ctx.stroke();
    	}
    },
    
    /*
     * This function calculates the grid spacing that it will be used 
     * by this geometry to draw the grid in order to reduce clutter. 
     */
    _calculateGrid: function() {
    	var grid = [];
    	
    	var time = SimileAjax.DateTime;
    	var u = this._unit;
    	var p = this._period;
        
        if (p == 0) return grid;
        
        // find the time units nearest to the time period
        if (p > time.gregorianUnitLengths[time.MILLENNIUM]) {
            unit = time.MILLENNIUM;	
        } else {
	        for (var unit = time.MILLENNIUM; unit > 0; unit--) {
	            if (time.gregorianUnitLengths[unit-1] <= p && p < time.gregorianUnitLengths[unit]) {
	                unit--;
	                break;
	            }
	        }
        }

        var t = u.cloneValue(this._earliestDate);

        do {
	        time.roundDownToInterval(t, unit, this._timeZone, 1, 0);
	        var x = this.toScreen(u.toNumber(t));
	        switch (unit) {
	        	case time.SECOND:
                  var l = t.toLocaleTimeString();
	        	  break;
	        	case time.MINUTE:
	        	  var m = t.getMinutes();
                  var l = t.getHours() + ":" + ((m < 10) ? "0" : "") + m;
                  break;
                case time.HOUR:
                  var l = t.getHours() + ":00";
                  break;
	        	case time.DAY:
	        	case time.WEEK:
                case time.MONTH:
                  var l = t.toLocaleDateString();
                  break;  
                case time.YEAR:
                case time.DECADE:
                case time.CENTURY:
                case time.MILLENNIUM:
	        	  var l = t.getUTCFullYear();
	        	  break;
	        }
	        if (x > 0) { 
		        grid.push({ x: x, label: l });
	        }
	        time.incrementByInterval(t, unit, this._timeZone);
        } while (t.getTime() < this._latestDate.getTime());
        
        return grid;
    },
        
    /*
     * Update the values that are used by the paint function so that
     * we don't have to calculate them at every repaint.
     */
    _updateMappedValues: function() {
    	if (this._latestDate && this._earliestDate) {
	        this._period = this._latestDate.getTime() - this._earliestDate.getTime();
	        this._mappedPeriod = this._map.direct(this._period);
    	} else {
    		this._period = 0;
    		this._mappedPeriod = 0;
    	}
    }
    
}

// --------------------------------------------------------------

/**
 * This is the constructor for the magnifying time geometry.
 * Users can interact with this geometry and 'magnify' certain areas of the
 * plot to see the plot enlarged and resolve details that would otherwise
 * get lost or cluttered with a linear time geometry.
 * 
 * @constructor
 */
Timeplot.MagnifyingTimeGeometry = function(params) {
    Timeplot.DefaultTimeGeometry.apply(this, arguments);
        
    var g = this;
    this._MagnifyingMap = {
        direct: function(t) {
        	if (t < g._leftTimeMargin) {
        		var x = t * g._leftRate;
        	} else if ( g._leftTimeMargin < t && t < g._rightTimeMargin ) {
        		var x = t * g._expandedRate + g._expandedTimeTranslation;
        	} else {
        		var x = t * g._rightRate + g._rightTimeTranslation;
        	}
        	return x;
        },
        inverse: function(x) {
            if (x < g._leftScreenMargin) {
                var t = x / g._leftRate;
            } else if ( g._leftScreenMargin < x && x < g._rightScreenMargin ) {
                var t = x / g._expandedRate + g._expandedScreenTranslation;
            } else {
                var t = x / g._rightRate + g._rightScreenTranslation;
            }
            return t;
        }
    }

    this._mode = "lin";
    this._map = this._linMap;
};

Object.extend(Timeplot.MagnifyingTimeGeometry.prototype,Timeplot.DefaultTimeGeometry.prototype);

/**
 * Initialize this geometry associating it with the given timeplot and 
 * register the geometry event handlers to the timeplot so that it can
 * interact with the user.
 */
Timeplot.MagnifyingTimeGeometry.prototype.initialize = function(timeplot) {
    Timeplot.DefaultTimeGeometry.prototype.initialize.apply(this, arguments);

    if (!this._lens) {
        this._lens = this._timeplot.putDiv("lens","timeplot-lens");
    }

    var period = 1000 * 60 * 60 * 24 * 30; // a month in the magnifying lens

    var geometry = this;
    
    var magnifyWith = function(lens) {
        var aperture = lens.clientWidth;
        var loc = geometry._timeplot.locate(lens);
        geometry.setMagnifyingParams(loc.x + aperture / 2, aperture, period);
        geometry.actMagnifying();
        geometry._timeplot.paint();
    }
    
    var canvasMouseDown = function(elmt, evt, target) {
        geometry._canvas.startCoords = SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
        geometry._canvas.pressed = true;
    }
    
    var canvasMouseUp = function(elmt, evt, target) {
        geometry._canvas.pressed = false;
        var coords = SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
        if (Timeplot.Math.isClose(coords,geometry._canvas.startCoords,5)) {
            geometry._lens.style.display = "none";
            geometry.actLinear();
            geometry._timeplot.paint();
        } else {
	        geometry._lens.style.cursor = "move";
	        magnifyWith(geometry._lens);
        }
    }

    var canvasMouseMove = function(elmt, evt, target) {
        if (geometry._canvas.pressed) {
            var coords = SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
            if (coords.x < 0) coords.x = 0;
            if (coords.x > geometry._canvas.width) coords.x = geometry._canvas.width;
            geometry._timeplot.placeDiv(geometry._lens, {
                left: geometry._canvas.startCoords.x,
                width: coords.x - geometry._canvas.startCoords.x,
                bottom: 0,
                height: geometry._canvas.height,
                display: "block"
            });
        }
    }

    var lensMouseDown = function(elmt, evt, target) {
        geometry._lens.startCoords = SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);;
        geometry._lens.pressed = true; 
    }
    
    var lensMouseUp = function(elmt, evt, target) {
        geometry._lens.pressed = false;
    }
    
    var lensMouseMove = function(elmt, evt, target) {
        if (geometry._lens.pressed) {
            var coords = SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
            var lens = geometry._lens;
            var left = lens.offsetLeft + coords.x - lens.startCoords.x;
            if (left < geometry._timeplot._paddingX) left = geometry._timeplot._paddingX;
            if (left + lens.clientWidth > geometry._canvas.width - geometry._timeplot._paddingX) left = geometry._canvas.width - lens.clientWidth + geometry._timeplot._paddingX;
            lens.style.left = left;
            magnifyWith(lens);
        }
    }
    
    if (!this._canvas.instrumented) {
        SimileAjax.DOM.registerEvent(this._canvas, "mousedown", canvasMouseDown);
        SimileAjax.DOM.registerEvent(this._canvas, "mousemove", canvasMouseMove);
        SimileAjax.DOM.registerEvent(this._canvas, "mouseup"  , canvasMouseUp);
        SimileAjax.DOM.registerEvent(this._canvas, "mouseup"  , lensMouseUp);
        this._canvas.instrumented = true;
    }
    
    if (!this._lens.instrumented) {
	    SimileAjax.DOM.registerEvent(this._lens, "mousedown", lensMouseDown);
	    SimileAjax.DOM.registerEvent(this._lens, "mousemove", lensMouseMove);
        SimileAjax.DOM.registerEvent(this._lens, "mouseup"  , lensMouseUp);
    	SimileAjax.DOM.registerEvent(this._lens, "mouseup"  , canvasMouseUp);
    	this._lens.instrumented = true;
    }
}

/**
 * Set the Magnifying parameters. c is the location in pixels where the Magnifying
 * center should be located in the timeplot, a is the aperture in pixel of
 * the Magnifying and b is the time period in milliseconds that the Magnifying 
 * should span.
 */
Timeplot.MagnifyingTimeGeometry.prototype.setMagnifyingParams = function(c,a,b) {
    a = a / 2;
    b = b / 2;

    var w = this._canvas.width;
    var d = this._period;

    if (c < 0) c = 0;
    if (c > w) c = w;
    
    if (c - a < 0) a = c;
    if (c + a > w) a = w - c;
    
    var ct = this.fromScreen(c) - this._earliestDate.getTime();
    if (ct - b < 0) b = ct;
    if (ct + b > d) b = d - ct;

    this._centerX = c;
    this._centerTime = ct;
    this._aperture = a;
    this._aperturePeriod = b;
    
    this._leftScreenMargin = this._centerX - this._aperture;
    this._rightScreenMargin = this._centerX + this._aperture;
    this._leftTimeMargin = this._centerTime - this._aperturePeriod;
    this._rightTimeMargin = this._centerTime + this._aperturePeriod;
        
    this._leftRate = (c - a) / (ct - b);
    this._expandedRate = a / b;
    this._rightRate = (w - c - a) / (d - ct - b);

    this._expandedTimeTranslation = this._centerX - this._centerTime * this._expandedRate; 
    this._expandedScreenTranslation = this._centerTime - this._centerX / this._expandedRate;
    this._rightTimeTranslation = (c + a) - (ct + b) * this._rightRate;
    this._rightScreenTranslation = (ct + b) - (c + a) / this._rightRate;

    this._updateMappedValues();
}

/*
 * Turn magnification off.
 */
Timeplot.MagnifyingTimeGeometry.prototype.actLinear = function() {
    this._mode = "lin";
    this._map = this._linMap;
    this.reset();
}

/*
 * Turn magnification on.
 */
Timeplot.MagnifyingTimeGeometry.prototype.actMagnifying = function() {
    this._mode = "Magnifying";
    this._map = this._MagnifyingMap;
    this.reset();
}

/*
 * Toggle magnification.
 */
Timeplot.MagnifyingTimeGeometry.prototype.toggle = function() {
    if (this._mode == "Magnifying") {
        this.actLinear();
    } else {
        this.actMagnifying();
    }
}

