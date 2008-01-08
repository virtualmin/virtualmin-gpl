/**
 * Color
 *
 * @fileOverview Color
 * @name Color
 */

/*
 * Inspired by Plotr
 * Copyright 2007 (c) Bas Wenneker <sabmann[a]gmail[d]com>
 * For use under the BSD license. <http://www.solutoire.com/plotr>
 */

/**
 * Create a Color object that can be used to manipulate colors programmatically.
 */
Timeplot.Color = function(color) {
    this._fromHex(color);
};

Timeplot.Color.prototype = {

    /**
     * Sets the RGB values of this coor
     * 
     * @param {Number} r,g,b    Red green and blue values (between 0 and 255)
     */
    set: function (r,g,b,a) {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = (a) ? a : 1.0;
        return this.check();
    },

    /**
     * Set the color transparency
     * 
     * @param {float} a   Transparency value, between 0.0 (fully transparent) and 1.0 (fully opaque).
     */
    transparency: function(a) {
    	this.a = a;
    	return this.check();
    },
    
    /**
     * Lightens the color.
     * 
     * @param {integer} level   Level to lighten the color with.
     */
    lighten: function(level) {
        var color = new Timeplot.Color();
        return color.set(
            this.r += parseInt(level, 10),
            this.g += parseInt(level, 10),
            this.b += parseInt(level, 10)
        );
    },

    /**
     * Darkens the color.
     * 
     * @param {integer} level   Level to darken the color with.
     */
    darken: function(level){
        var color = new Timeplot.Color();
        return color.set(
            this.r -= parseInt(level, 10),
            this.g -= parseInt(level, 10),
            this.b -= parseInt(level, 10)
        );
    },

    /**
     * Checks and validates if the hex values r, g and b are
     * between 0 and 255.
     */
    check: function() {
        if (this.r > 255) { 
        	this.r = 255;
        } else if (this.r < 0){
        	this.r = 0;
        }
        if (this.g > 255) {
        	this.g = 255;
        } else if (this.g < 0) {
        	this.g = 0;
        }
        if (this.b > 255){
        	this.b = 255;
        } else if (this.b < 0){
        	this.b = 0;
        }
        if (this.a > 1.0){
            this.a = 1.0;
        } else if (this.a < 0.0){
            this.a = 0.0;
        }
        return this;
    },

    /**
     * Returns a string representation of this color.
     * 
     * @param {float} alpha   (optional) Transparency value, between 0.0 (fully transparent) and 1.0 (fully opaque).
     */
    toString: function(alpha) {
        var a = (alpha) ? alpha : ((this.a) ? this.a : 1.0);
        return 'rgba(' + this.r + ',' + this.g + ',' + this.b + ',' + a + ')';
    },

    /**
     * Returns the hexadecimal representation of this color (without the alpha channel as hex colors don't support it)
     */
    toHexString: function() {
    	return "#" + this._toHex(this.r) + this._toHex(this.g) + this._toHex(this.b); 
    },
    
    /*
     * Parses and stores the hex values of the input color string.
     * 
     * @param {String} color    Hex or rgb() css string.
     */
    _fromHex: function(color) {
        if(/^#?([\da-f]{3}|[\da-f]{6})$/i.test(color)){
            color = color.replace(/^#/, '').replace(/^([\da-f])([\da-f])([\da-f])$/i, "$1$1$2$2$3$3");
            this.r = parseInt(color.substr(0,2), 16);
            this.g = parseInt(color.substr(2,2), 16);
            this.b = parseInt(color.substr(4,2), 16);
        } else if(/^rgb *\( *\d{0,3} *, *\d{0,3} *, *\d{0,3} *\)$/i.test(color)){
            color = color.match(/^rgb *\( *(\d{0,3}) *, *(\d{0,3}) *, *(\d{0,3}) *\)$/i);
            this.r = parseInt(color[1], 10);
            this.g = parseInt(color[2], 10);
            this.b = parseInt(color[3], 10);
        }
        this.a = 1.0;
        return this.check();
    },
    
    /*
     * Returns an hexadecimal representation of a 8 bit integer 
     */
    _toHex: function(dec) {
        var hex = "0123456789ABCDEF"
        if (dec < 0) return "00";
        if (dec > 255) return "FF";
        var i = Math.floor(dec / 16);
        var j = dec % 16;
        return hex.charAt(i) + hex.charAt(j);
    }

};