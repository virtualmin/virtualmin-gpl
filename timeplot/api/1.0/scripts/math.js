/**
 * Math Utility functions
 * 
 * @fileOverview Math Utility functions
 * @name Math
 */

Timeplot.Math = { 

    /**
     * Evaluates the range (min and max values) of the given array
     */
    range: function(f) {
        var F = f.length;
        var min = Number.MAX_VALUE;
        var max = Number.MIN_VALUE;

        for (var t = 0; t < F; t++) {
            var value = f[t];
            if (value < min) {
                min = value;
            }
            if (value > max) {
                max = value;
            }    
        }

        return {
            min: min,
            max: max
        }
    },

    /**
     * Evaluates the windows average of a given array based on the
     * given window size
     */
    movingAverage: function(f, size) {
        var F = f.length;
        var g = new Array(F);
        for (var n = 0; n < F; n++) {
            var value = 0;
            for (var m = n - size; m < n + size; m++) {
                if (m < 0) {
                    var v = f[0];
                } else if (m >= F) {
                    var v = g[n-1];
                } else {
                    var v = f[m];
                }
                value += v;
            }
            g[n] = value / (2 * size);
        }
        return g;
    },

    /**
     * Returns an array with the integral of the given array
     */
    integral: function(f) {
        var F = f.length;

        var g = new Array(F);
        var sum = 0;

        for (var t = 0; t < F; t++) {
           sum += f[t];
           g[t] = sum;  
        }

        return g;
    },

    /**
     * Normalizes an array so that its complete integral is 1.
     * This is useful to obtain arrays that preserve the overall
     * integral of a convolution. 
     */
    normalize: function(f) {
        var F = f.length;
        var sum = 0.0;

        for (var t = 0; t < F; t++) {
            sum += f[t];
        }

        for (var t = 0; t < F; t++) {
            f[t] /= sum;
        }

        return f;
    },

    /**
     * Calculates the convolution between two arrays
     */
    convolution: function(f,g) {
        var F = f.length;
        var G = g.length;

        var c = new Array(F);

        for (var m = 0; m < F; m++) {
            var r = 0;
            var end = (m + G < F) ? m + G : F;
            for (var n = m; n < end; n++) {
                var a = f[n - G];
                var b = g[n - m];
                r += a * b;
            }
            c[m] = r;
        }

        return c;
    },

    // ------ Array generators ------------------------------------------------- 
    // Functions that generate arrays based on mathematical functions
    // Normally these are used to produce operators by convolving them with the input array
    // The returned arrays have the property of having 

    /**
     * Generate the heavyside step function of given size
     */
    heavyside: function(size) {
        var f =  new Array(size);
        var value = 1 / size;
        for (var t = 0; t < size; t++) {
            f[t] = value;
        }
        return f;
    },

    /**
     * Generate the gaussian function so that at the given 'size' it has value 'threshold'
     * and make sure its integral is one.
     */
    gaussian: function(size, threshold) {
        with (Math) {
            var radius = size / 2;
            var variance = radius * radius / log(threshold); 
            var g = new Array(size);
            for (var t = 0; t < size; t++) {
                var l = t - radius;
                g[t] = exp(-variance * l * l);
            }
        }

        return this.normalize(g);
    },

    // ---- Utility Methods --------------------------------------------------

    /**
     * Return x with n significant figures 
     */
    round: function(x,n) {
        with (Math) {
            if (abs(x) > 1) {
                var l = floor(log(x)/log(10));
                var d = round(exp((l-n+1)*log(10)));
                var y = round(round(x / d) * d);
                return y;
            } else {
                log("FIXME(SM): still to implement for 0 < abs(x) < 1");
                return x;
            }
        }
    },
    
    /**
     * Return the hyperbolic tangent of x
     */
    tanh: function(x) {
    	if (x > 5) {
    		return 1;
    	} else if (x < 5) {
    		return -1;
    	} else {
	    	var expx2 = Math.exp(2 * x);
	    	return (expx2 - 1) / (expx2 + 1);
    	}
    },
    
    /** 
     * Returns true if |a.x - b.x| < value && | a.y - b.y | < value
     */
    isClose: function(a,b,value) {
    	return (a && b && Math.abs(a.x - b.x) < value && Math.abs(a.y - b.y) < value);
    }

}