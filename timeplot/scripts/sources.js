/**
 * Sources
 * 
 * @fileOverview Sources
 * @name Sources
 */

/**
 * Timeplot.DefaultEventSource is an extension of Timeline.DefaultEventSource
 * and therefore reuses the exact same event loading subsystem that
 * Timeline uses.
 * 
 * @constructor
 */
Timeplot.DefaultEventSource = function(eventIndex) {
	Timeline.DefaultEventSource.apply(this, arguments);
};

Object.extend(Timeplot.DefaultEventSource.prototype, Timeline.DefaultEventSource.prototype);

/**
 * Function used by Timeplot to load time series data from a text file.
 */
Timeplot.DefaultEventSource.prototype.loadText = function(text, separator, url, filter) {

    if (text == null) {
        return;
    }

    this._events.maxValues = new Array();
    var base = this._getBaseURL(url);

    var dateTimeFormat = 'iso8601';
    var parseDateTimeFunction = this._events.getUnit().getParser(dateTimeFormat);

    var data = this._parseText(text, separator);

    var added = false;

    if (filter) {
        data = filter(data);
    }

    if (data) {
        for (var i = 0; i < data.length; i++){
            var row = data[i];
            if (row.length > 1) {
		        var evt = new Timeplot.DefaultEventSource.NumericEvent(
		            parseDateTimeFunction(row[0]),
		            row.slice(1)
		        );
		        this._events.add(evt);
		        added = true;
            }
        }
    }

    if (added) {
        this._fire("onAddMany", []);
    }
}

/*
 * Parse the data file.
 * 
 * Adapted from http://www.kawa.net/works/js/jkl/js/jkl-parsexml.js by Yusuke Kawasaki
 */
Timeplot.DefaultEventSource.prototype._parseText = function (text, separator) {
    text = text.replace( /\r\n?/g, "\n" ); // normalize newlines
    var pos = 0;
    var len = text.length;
    var table = [];
    while (pos < len) {
        var line = [];
        if (text.charAt(pos) != '#') { // if it's not a comment, process
            while (pos < len) {
                if (text.charAt(pos) == '"') {            // "..." quoted column
                    var nextquote = text.indexOf('"', pos+1 );
                    while (nextquote<len && nextquote > -1) {
                        if (text.charAt(nextquote+1) != '"') {
                            break;                          // end of column
                        }
                        nextquote = text.indexOf('"', nextquote + 2);
                    }
                    if ( nextquote < 0 ) {
                        // unclosed quote
                    } else if (text.charAt(nextquote + 1) == separator) { // end of column
                        var quoted = text.substr(pos + 1, nextquote-pos - 1);
                        quoted = quoted.replace(/""/g,'"');
                        line[line.length] = quoted;
                        pos = nextquote + 2;
                        continue;
                    } else if (text.charAt(nextquote + 1) == "\n" || // end of line
                               len == nextquote + 1 ) {              // end of file
                        var quoted = text.substr(pos + 1, nextquote-pos - 1);
                        quoted = quoted.replace(/""/g,'"');
                        line[line.length] = quoted;
                        pos = nextquote + 2;
                        break;
                    } else {
                        // invalid column
                    }
                }
                var nextseparator = text.indexOf(separator, pos);
                var nextnline = text.indexOf("\n", pos);
                if (nextnline < 0) nextnline = len;
                if (nextseparator > -1 && nextseparator < nextnline) {
                    line[line.length] = text.substr(pos, nextseparator-pos);
                    pos = nextseparator + 1;
                } else {                                    // end of line
                    line[line.length] = text.substr(pos, nextnline-pos);
                    pos = nextnline + 1;
                    break;
                }
            }
        } else { // if it's a comment, ignore
            var nextnline = text.indexOf("\n", pos);
            pos = (nextnline > -1) ? nextnline + 1 : cur;
        }
        if (line.length > 0) {
            table[table.length] = line;                 // push line
        }
    }
    if (table.length < 0) return;                     // null data
    return table;
}

/**
 * Return the range of the loaded data
 */
Timeplot.DefaultEventSource.prototype.getRange = function() {
	var earliestDate = this.getEarliestDate();
	var latestDate = this.getLatestDate();
    return {
        earliestDate: (earliestDate) ? earliestDate : null,
        latestDate: (latestDate) ? latestDate : null,
        min: 0,
        max: 0
    };
}

// -----------------------------------------------------------------------

/**
 * A NumericEvent is an Event that also contains an array of values, 
 * one for each columns in the loaded data file.
 * 
 * @constructor
 */
Timeplot.DefaultEventSource.NumericEvent = function(time, values) {
    this._id = "e" + Math.round(Math.random() * 1000000);
    this._time = time;
    this._values = values;
};

Timeplot.DefaultEventSource.NumericEvent.prototype = {
    getID:          function() { return this._id; },
    getTime:        function() { return this._time; },
    getValues:      function() { return this._values; },

    // these are required by the EventSource
    getStart:       function() { return this._time; },
    getEnd:         function() { return this._time; }
};

// -----------------------------------------------------------------------

/**
 * A DataSource represent an abstract class that represents a monodimensional time series.
 * 
 * @constructor
 */
Timeplot.DataSource = function(eventSource) {
    this._eventSource = eventSource;
    var source = this;
    this._processingListener = {
        onAddMany: function() { source._process(); },
        onClear:   function() { source._clear(); }
    }
    this.addListener(this._processingListener);
    this._listeners = [];
};

Timeplot.DataSource.prototype = {
  
    _clear: function() {
        this._data = null;
        this._range = null;
    },

    _process: function() {
        this._data = {
            times: new Array(),
            values: new Array()
        };
        this._range = {
            earliestDate: null,
            latestDate: null,
            min: 0,
            max: 0
        };
    },

    /**
     * Return the range of this data source
     */
    getRange: function() {
        return this._range;
    },

    /**
     * Return the actual data that this data source represents.
     * NOTE: _data = { times: [], values: [] }
     */
    getData: function() {
        return this._data;
    },
    
    /**
     * Return the value associate with the given time in this time series
     */
    getValue: function(t) {
    	if (this._data) {
	    	for (var i = 0; i < this._data.times.length; i++) {
	    		var l = this._data.times[i];
	    		if (l > t) {
	    			return this._data.values[i];
	    		}
	    	}
    	}
    	return 0;
    },

    /**
     * Add a listener to the underlying event source
     */
    addListener: function(listener) {
        this._eventSource.addListener(listener);
    },

    /**
     * Remove a listener from the underlying event source
     */
    removeListener: function(listener) {
        this._eventSource.removeListener(listener);
    },

    /**
     * Replace a listener from the underlying event source
     */
    replaceListener: function(oldListener, newListener) {
        this.removeListener(oldListener);
        this.addListener(newListener);
    }

}

// -----------------------------------------------------------------------

/**
 * Implementation of a DataSource that extracts the time series out of a 
 * single column from the events
 * 
 * @constructor
 */
Timeplot.ColumnSource = function(eventSource, column) {
    Timeplot.DataSource.apply(this, arguments);
    this._column = column - 1;
};

Object.extend(Timeplot.ColumnSource.prototype,Timeplot.DataSource.prototype);

Timeplot.ColumnSource.prototype.dispose = function() {
    this.removeListener(this._processingListener);
    this._clear();
}

Timeplot.ColumnSource.prototype._process = function() {
    var count = this._eventSource.getCount();
    var times = new Array(count);
    var values = new Array(count);
    var min = Number.MAX_VALUE;
    var max = Number.MIN_VALUE;
    var i = 0;

    var iterator = this._eventSource.getAllEventIterator();
    while (iterator.hasNext()) {
        var event = iterator.next();
        var time = event.getTime();
        times[i] = time;
        var value = this._getValue(event);
        if (!isNaN(value)) {
           if (value < min) {
               min = value;
           }
           if (value > max) {
               max = value;
           }    
            values[i] = value;
        }
        i++;
    }

    this._data = {
        times: times,
        values: values
    };

    this._range = {
        earliestDate: this._eventSource.getEarliestDate(),
        latestDate: this._eventSource.getLatestDate(),
        min: min,
        max: max
    };
}

Timeplot.ColumnSource.prototype._getValue = function(event) {
    return parseFloat(event.getValues()[this._column]);
}

// ---------------------------------------------------------------

/**
 * Data Source that generates the time series out of the difference
 * between the first and the second column
 * 
 * @constructor
 */
Timeplot.ColumnDiffSource = function(eventSource, column1, column2) {
    Timeplot.ColumnSource.apply(this, arguments);
    this._column2 = column2 - 1;
};

Object.extend(Timeplot.ColumnDiffSource.prototype,Timeplot.ColumnSource.prototype);

Timeplot.ColumnDiffSource.prototype._getValue = function(event) {
    var a = parseFloat(event.getValues()[this._column]);
    var b = parseFloat(event.getValues()[this._column2]);
    return a - b;
}
