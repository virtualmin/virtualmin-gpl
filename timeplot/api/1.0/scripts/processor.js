/**
 * Processing Data Source
 * 
 * @fileOverview Processing Data Source and Operators
 * @name Processor
 */

/* -----------------------------------------------------------------------------
 * Operators
 * 
 * These are functions that can be used directly as Timeplot.Processor operators
 * ----------------------------------------------------------------------------- */

Timeplot.Operator = { 

    /**
     * This is the operator used when you want to draw the cumulative sum
     * of a time series and not, for example, their daily values.
     */
    sum: function(data, params) {
        return Timeplot.Math.integral(data.values);
    },

    /**
     * This is the operator that is used to 'smooth' a given time series
     * by taking the average value of a moving window centered around
     * each value. The size of the moving window is influenced by the 'size'
     * parameters in the params map.
     */
    average: function(data, params) {
        var size = ("size" in params) ? params.size : 30;
        var result = Timeplot.Math.movingAverage(data.values, size);
        return result;
    }
}

/*==================================================
 *  Processing Data Source
 *==================================================*/

/**
 * A Processor is a special DataSource that can apply an Operator
 * to the DataSource values and thus return a different one.
 * 
 * @constructor
 */
Timeplot.Processor = function(dataSource, operator, params) {
    this._dataSource = dataSource;
    this._operator = operator;
    this._params = params;

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

    var processor = this;
    this._processingListener = {
        onAddMany: function() { processor._process(); },
        onClear:   function() { processor._clear(); }
    }
    this.addListener(this._processingListener);
};

Timeplot.Processor.prototype = {

    _clear: function() {
        this.removeListener(this._processingListener);
        this._dataSource._clear();
    },

    _process: function() {
        // this method requires the dataSource._process() method to be
        // called first as to setup the data and range used below
        // this should be guaranteed by the order of the listener registration  

        var data = this._dataSource.getData();
        var range = this._dataSource.getRange();

        var newValues = this._operator(data, this._params);
        var newValueRange = Timeplot.Math.range(newValues);

        this._data = {
            times: data.times,
            values: newValues
        };

        this._range = {
            earliestDate: range.earliestDate,
            latestDate: range.latestDate,
            min: newValueRange.min,
            max: newValueRange.max
        };
    },

    getRange: function() {
        return this._range;
    },

    getData: function() {
        return this._data;
    },
    
    getValue: Timeplot.DataSource.prototype.getValue,

    addListener: function(listener) {
        this._dataSource.addListener(listener);
    },

    removeListener: function(listener) {
        this._dataSource.removeListener(listener);
    }
}
