/**
 * @fileOverview Graphics utility functions and constants
 * @name SimileAjax.Graphics
 */

SimileAjax.Graphics = new Object();

/**
 * A boolean value indicating whether PNG translucency is supported on the
 * user's browser or not.
 *
 * @type Boolean
 */
SimileAjax.Graphics.pngIsTranslucent = (!SimileAjax.Platform.browser.isIE) || (SimileAjax.Platform.browser.majorVersion > 6);

/*==================================================
 *  Opacity, translucency
 *==================================================
 */
SimileAjax.Graphics._createTranslucentImage1 = function(url, verticalAlign) {
    var elmt = document.createElement("img");
    elmt.setAttribute("src", url);
    if (verticalAlign != null) {
        elmt.style.verticalAlign = verticalAlign;
    }
    return elmt;
};
SimileAjax.Graphics._createTranslucentImage2 = function(url, verticalAlign) {
    var elmt = document.createElement("img");
    elmt.style.width = "1px";  // just so that IE will calculate the size property
    elmt.style.height = "1px";
    elmt.style.filter = "progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + url +"', sizingMethod='image')";
    elmt.style.verticalAlign = (verticalAlign != null) ? verticalAlign : "middle";
    return elmt;
};

/**
 * Creates a DOM element for an <code>img</code> tag using the URL given. This
 * is a convenience method that automatically includes the necessary CSS to
 * allow for translucency, even on IE.
 * 
 * @function
 * @param {String} url the URL to the image
 * @param {String} verticalAlign the CSS value for the image's vertical-align
 * @return {Element} a DOM element containing the <code>img</code> tag
 */
SimileAjax.Graphics.createTranslucentImage = SimileAjax.Graphics.pngIsTranslucent ?
    SimileAjax.Graphics._createTranslucentImage1 :
    SimileAjax.Graphics._createTranslucentImage2;

SimileAjax.Graphics._createTranslucentImageHTML1 = function(url, verticalAlign) {
    return "<img src=\"" + url + "\"" +
        (verticalAlign != null ? " style=\"vertical-align: " + verticalAlign + ";\"" : "") +
        " />";
};
SimileAjax.Graphics._createTranslucentImageHTML2 = function(url, verticalAlign) {
    var style = 
        "width: 1px; height: 1px; " +
        "filter:progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + url +"', sizingMethod='image');" +
        (verticalAlign != null ? " vertical-align: " + verticalAlign + ";" : "");
        
    return "<img src='" + url + "' style=\"" + style + "\" />";
};

/**
 * Creates an HTML string for an <code>img</code> tag using the URL given.
 * This is a convenience method that automatically includes the necessary CSS
 * to allow for translucency, even on IE.
 * 
 * @function
 * @param {String} url the URL to the image
 * @param {String} verticalAlign the CSS value for the image's vertical-align
 * @return {String} a string containing the <code>img</code> tag
 */
SimileAjax.Graphics.createTranslucentImageHTML = SimileAjax.Graphics.pngIsTranslucent ?
    SimileAjax.Graphics._createTranslucentImageHTML1 :
    SimileAjax.Graphics._createTranslucentImageHTML2;

/**
 * Sets the opacity on the given DOM element.
 *
 * @param {Element} elmt the DOM element to set the opacity on
 * @param {Number} opacity an integer from 0 to 100 specifying the opacity
 */
SimileAjax.Graphics.setOpacity = function(elmt, opacity) {
    if (SimileAjax.Platform.browser.isIE) {
        elmt.style.filter = "progid:DXImageTransform.Microsoft.Alpha(Style=0,Opacity=" + opacity + ")";
    } else {
        var o = (opacity / 100).toString();
        elmt.style.opacity = o;
        elmt.style.MozOpacity = o;
    }
};

/*==================================================
 *  Bubble
 *==================================================
 */
SimileAjax.Graphics._bubbleMargins = {
    top:      33,
    bottom:   42,
    left:     33,
    right:    40
}

// pixels from boundary of the whole bubble div to the tip of the arrow
SimileAjax.Graphics._arrowOffsets = { 
    top:      0,
    bottom:   9,
    left:     1,
    right:    8
}

SimileAjax.Graphics._bubblePadding = 15;
SimileAjax.Graphics._bubblePointOffset = 6;
SimileAjax.Graphics._halfArrowWidth = 18;

/**
 * Creates a nice, rounded bubble popup with the given content in a div,
 * page coordinates and a suggested width. The bubble will point to the 
 * location on the page as described by pageX and pageY.  All measurements 
 * should be given in pixels.
 *
 * @param {Element} the content div
 * @param {Number} pageX the x coordinate of the point to point to
 * @param {Number} pageY the y coordinate of the point to point to
 * @param {Number} contentWidth a suggested width of the content
 * @param {String} orientation a string ("top", "bottom", "left", or "right")
 *   that describes the orientation of the arrow on the bubble
 */
SimileAjax.Graphics.createBubbleForContentAndPoint = function(div, pageX, pageY, contentWidth, orientation) {
    if (typeof contentWidth != "number") {
        contentWidth = 300;
    }
    
    div.style.position = "absolute";
    div.style.left = "-5000px";
    div.style.top = "0px";
    div.style.width = contentWidth + "px";
    document.body.appendChild(div);
    
    window.setTimeout(function() {
        var width = div.scrollWidth + 10;
        var height = div.scrollHeight + 10;
        
        var bubble = SimileAjax.Graphics.createBubbleForPoint(pageX, pageY, width, height, orientation);
        
        document.body.removeChild(div);
        div.style.position = "static";
        div.style.left = "";
        div.style.top = "";
        div.style.width = width + "px";
        bubble.content.appendChild(div);
    }, 200);
};

/**
 * Creates a nice, rounded bubble popup with the given page coordinates and
 * content dimensions.  The bubble will point to the location on the page
 * as described by pageX and pageY.  All measurements should be given in
 * pixels.
 *
 * @param {Number} pageX the x coordinate of the point to point to
 * @param {Number} pageY the y coordinate of the point to point to
 * @param {Number} contentWidth the width of the content box in the bubble
 * @param {Number} contentHeight the height of the content box in the bubble
 * @param {String} orientation a string ("top", "bottom", "left", or "right")
 *   that describes the orientation of the arrow on the bubble
 * @return {Element} a DOM element for the newly created bubble
 */
SimileAjax.Graphics.createBubbleForPoint = function(pageX, pageY, contentWidth, contentHeight, orientation) {
    function getWindowDims() {
        if (typeof window.innerHeight == 'number') {
            return { w:window.innerWidth, h:window.innerHeight }; // Non-IE
        } else if (document.documentElement && document.documentElement.clientHeight) {
            return { // IE6+, in "standards compliant mode"
                w:document.documentElement.clientWidth,
                h:document.documentElement.clientHeight
            };
        } else if (document.body && document.body.clientHeight) {
            return { // IE 4 compatible
                w:document.body.clientWidth,
                h:document.body.clientHeight
            };
        }
    }

    var close = function() { 
        if (!bubble._closed) {
            document.body.removeChild(bubble._div);
            bubble._doc = null;
            bubble._div = null;
            bubble._content = null;
            bubble._closed = true;
        }
    }
    var bubble = {
        _closed:   false
    };
    
    var dims = getWindowDims();
    var docWidth = dims.w;
    var docHeight = dims.h;

    var margins = SimileAjax.Graphics._bubbleMargins;
    contentWidth = parseInt(contentWidth, 10); // harden against bad input bugs
    contentHeight = parseInt(contentHeight, 10); // getting numbers-as-strings
    var bubbleWidth = margins.left + contentWidth + margins.right;
    var bubbleHeight = margins.top + contentHeight + margins.bottom;
    
    var pngIsTranslucent = SimileAjax.Graphics.pngIsTranslucent;
    var urlPrefix = SimileAjax.urlPrefix;
    
    var setImg = function(elmt, url, width, height) {
        elmt.style.position = "absolute";
        elmt.style.width = width + "px";
        elmt.style.height = height + "px";
        if (pngIsTranslucent) {
            elmt.style.background = "url(" + url + ")";
        } else {
            elmt.style.filter = "progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + url +"', sizingMethod='crop')";
        }
    }
    var div = document.createElement("div");
    div.style.width = bubbleWidth + "px";
    div.style.height = bubbleHeight + "px";
    div.style.position = "absolute";
    div.style.zIndex = 1000;
    
    var layer = SimileAjax.WindowManager.pushLayer(close, true, div);
    bubble._div = div;
    bubble.close = function() { SimileAjax.WindowManager.popLayer(layer); }
    
    var divInner = document.createElement("div");
    divInner.style.width = "100%";
    divInner.style.height = "100%";
    divInner.style.position = "relative";
    div.appendChild(divInner);
    
    var createImg = function(url, left, top, width, height) {
        var divImg = document.createElement("div");
        divImg.style.left = left + "px";
        divImg.style.top = top + "px";
        setImg(divImg, url, width, height);
        divInner.appendChild(divImg);
    }
    
    createImg(urlPrefix + "images/bubble-top-left.png", 0, 0, margins.left, margins.top);
    createImg(urlPrefix + "images/bubble-top.png", margins.left, 0, contentWidth, margins.top);
    createImg(urlPrefix + "images/bubble-top-right.png", margins.left + contentWidth, 0, margins.right, margins.top);
    
    createImg(urlPrefix + "images/bubble-left.png", 0, margins.top, margins.left, contentHeight);
    createImg(urlPrefix + "images/bubble-right.png", margins.left + contentWidth, margins.top, margins.right, contentHeight);
    
    createImg(urlPrefix + "images/bubble-bottom-left.png", 0, margins.top + contentHeight, margins.left, margins.bottom);
    createImg(urlPrefix + "images/bubble-bottom.png", margins.left, margins.top + contentHeight, contentWidth, margins.bottom);
    createImg(urlPrefix + "images/bubble-bottom-right.png", margins.left + contentWidth, margins.top + contentHeight, margins.right, margins.bottom);
    
    var divClose = document.createElement("div");
    divClose.style.left = (bubbleWidth - margins.right + SimileAjax.Graphics._bubblePadding - 16 - 2) + "px";
    divClose.style.top = (margins.top - SimileAjax.Graphics._bubblePadding + 1) + "px";
    divClose.style.cursor = "pointer";
    setImg(divClose, urlPrefix + "images/close-button.png", 16, 16);
    SimileAjax.WindowManager.registerEventWithObject(divClose, "click", bubble, "close");
    divInner.appendChild(divClose);
        
    var divContent = document.createElement("div");
    divContent.style.position = "absolute";
    divContent.style.left = margins.left + "px";
    divContent.style.top = margins.top + "px";
    divContent.style.width = contentWidth + "px";
    divContent.style.height = contentHeight + "px";
    divContent.style.overflow = "auto";
    divContent.style.background = "white";
    divInner.appendChild(divContent);
    bubble.content = divContent;
    
    (function() {
        if (pageX - SimileAjax.Graphics._halfArrowWidth - SimileAjax.Graphics._bubblePadding > 0 &&
            pageX + SimileAjax.Graphics._halfArrowWidth + SimileAjax.Graphics._bubblePadding < docWidth) {
            
            var left = pageX - Math.round(contentWidth / 2) - margins.left;
            left = pageX < (docWidth / 2) ?
                Math.max(left, -(margins.left - SimileAjax.Graphics._bubblePadding)) : 
                Math.min(left, docWidth + (margins.right - SimileAjax.Graphics._bubblePadding) - bubbleWidth);
                
            if ((orientation && orientation == "top") || (!orientation && (pageY - SimileAjax.Graphics._bubblePointOffset - bubbleHeight > 0))) { // top
                var divImg = document.createElement("div");
                
                divImg.style.left = (pageX - SimileAjax.Graphics._halfArrowWidth - left) + "px";
                divImg.style.top = (margins.top + contentHeight) + "px";
                setImg(divImg, urlPrefix + "images/bubble-bottom-arrow.png", 37, margins.bottom);
                divInner.appendChild(divImg);
                
                div.style.left = left + "px";
                div.style.top = (pageY - SimileAjax.Graphics._bubblePointOffset - bubbleHeight + 
                    SimileAjax.Graphics._arrowOffsets.bottom) + "px";
                
                return;
            } else if ((orientation && orientation == "bottom") || (!orientation && (pageY + SimileAjax.Graphics._bubblePointOffset + bubbleHeight < docHeight))) { // bottom
                var divImg = document.createElement("div");
                
                divImg.style.left = (pageX - SimileAjax.Graphics._halfArrowWidth - left) + "px";
                divImg.style.top = "0px";
                setImg(divImg, urlPrefix + "images/bubble-top-arrow.png", 37, margins.top);
                divInner.appendChild(divImg);
                
                div.style.left = left + "px";
                div.style.top = (pageY + SimileAjax.Graphics._bubblePointOffset - 
                    SimileAjax.Graphics._arrowOffsets.top) + "px";
                
                return;
            }
        }
        
        var top = pageY - Math.round(contentHeight / 2) - margins.top;
        top = pageY < (docHeight / 2) ?
            Math.max(top, -(margins.top - SimileAjax.Graphics._bubblePadding)) : 
            Math.min(top, docHeight + (margins.bottom - SimileAjax.Graphics._bubblePadding) - bubbleHeight);
                
        if ((orientation && orientation == "left") || (!orientation && (pageX - SimileAjax.Graphics._bubblePointOffset - bubbleWidth > 0))) { // left
            var divImg = document.createElement("div");
            
            divImg.style.left = (margins.left + contentWidth) + "px";
            divImg.style.top = (pageY - SimileAjax.Graphics._halfArrowWidth - top) + "px";
            setImg(divImg, urlPrefix + "images/bubble-right-arrow.png", margins.right, 37);
            divInner.appendChild(divImg);
            
            div.style.left = (pageX - SimileAjax.Graphics._bubblePointOffset - bubbleWidth +
                SimileAjax.Graphics._arrowOffsets.right) + "px";
            div.style.top = top + "px";
        } else if ((orientation && orientation == "right") || (!orientation && (pageX - SimileAjax.Graphics._bubblePointOffset - bubbleWidth < docWidth))) { // right
            var divImg = document.createElement("div");
            
            divImg.style.left = "0px";
            divImg.style.top = (pageY - SimileAjax.Graphics._halfArrowWidth - top) + "px";
            setImg(divImg, urlPrefix + "images/bubble-left-arrow.png", margins.left, 37);
            divInner.appendChild(divImg);
            
            div.style.left = (pageX + SimileAjax.Graphics._bubblePointOffset - 
                SimileAjax.Graphics._arrowOffsets.left) + "px";
            div.style.top = top + "px";
        }
    })();
    
    document.body.appendChild(div);
    
    return bubble;
};

/**
 * Creates a floating, rounded message bubble in the center of the window for
 * displaying modal information, e.g. "Loading..."
 *
 * @param {Document} doc the root document for the page to render on
 * @param {Object} an object with two properties, contentDiv and containerDiv,
 *   consisting of the newly created DOM elements
 */
SimileAjax.Graphics.createMessageBubble = function(doc) {
    var containerDiv = doc.createElement("div");
    if (SimileAjax.Graphics.pngIsTranslucent) {
        var topDiv = doc.createElement("div");
        topDiv.style.height = "33px";
        topDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-top-left.png) top left no-repeat";
        topDiv.style.paddingLeft = "44px";
        containerDiv.appendChild(topDiv);
        
        var topRightDiv = doc.createElement("div");
        topRightDiv.style.height = "33px";
        topRightDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-top-right.png) top right no-repeat";
        topDiv.appendChild(topRightDiv);
        
        var middleDiv = doc.createElement("div");
        middleDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-left.png) top left repeat-y";
        middleDiv.style.paddingLeft = "44px";
        containerDiv.appendChild(middleDiv);
        
        var middleRightDiv = doc.createElement("div");
        middleRightDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-right.png) top right repeat-y";
        middleRightDiv.style.paddingRight = "44px";
        middleDiv.appendChild(middleRightDiv);
        
        var contentDiv = doc.createElement("div");
        middleRightDiv.appendChild(contentDiv);
        
        var bottomDiv = doc.createElement("div");
        bottomDiv.style.height = "55px";
        bottomDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-bottom-left.png) bottom left no-repeat";
        bottomDiv.style.paddingLeft = "44px";
        containerDiv.appendChild(bottomDiv);
        
        var bottomRightDiv = doc.createElement("div");
        bottomRightDiv.style.height = "55px";
        bottomRightDiv.style.background = "url(" + SimileAjax.urlPrefix + "images/message-bottom-right.png) bottom right no-repeat";
        bottomDiv.appendChild(bottomRightDiv);
    } else {
        containerDiv.style.border = "2px solid #7777AA";
        containerDiv.style.padding = "20px";
        containerDiv.style.background = "white";
        SimileAjax.Graphics.setOpacity(containerDiv, 90);
        
        var contentDiv = doc.createElement("div");
        containerDiv.appendChild(contentDiv);
    }
    
    return {
        containerDiv:   containerDiv,
        contentDiv:     contentDiv
    };
};

/*==================================================
 *  Animation
 *==================================================
 */

/**
 * Creates an animation for a function, and an interval of values.  The word
 * "animation" here is used in the sense of repeatedly calling a function with
 * a current value from within an interval, and a delta value.
 *
 * @param {Function} f a function to be called every 50 milliseconds throughout
 *   the animation duration, of the form f(current, delta), where current is
 *   the current value within the range and delta is the current change.
 * @param {Number} from a starting value
 * @param {Number} to an ending value
 * @param {Number} duration the duration of the animation in milliseconds
 * @param {Function} [cont] an optional function that is called at the end of
 *   the animation, i.e. a continuation.
 * @return {SimileAjax.Graphics._Animation} a new animation object
 */
SimileAjax.Graphics.createAnimation = function(f, from, to, duration, cont) {
    return new SimileAjax.Graphics._Animation(f, from, to, duration, cont);
};

SimileAjax.Graphics._Animation = function(f, from, to, duration, cont) {
    this.f = f;
    this.cont = (typeof cont == "function") ? cont : function() {};
    
    this.from = from;
    this.to = to;
    this.current = from;
    
    this.duration = duration;
    this.start = new Date().getTime();
    this.timePassed = 0;
};

/**
 * Runs this animation.
 */
SimileAjax.Graphics._Animation.prototype.run = function() {
    var a = this;
    window.setTimeout(function() { a.step(); }, 50);
};

/**
 * Increments this animation by one step, and then continues the animation with
 * <code>run()</code>.
 */
SimileAjax.Graphics._Animation.prototype.step = function() {
    this.timePassed += 50;
    
    var timePassedFraction = this.timePassed / this.duration;
    var parameterFraction = -Math.cos(timePassedFraction * Math.PI) / 2 + 0.5;
    var current = parameterFraction * (this.to - this.from) + this.from;
    
    try {
        this.f(current, current - this.current);
    } catch (e) {
    }
    this.current = current;
    
    if (this.timePassed < this.duration) {
        this.run();
    } else {
        this.f(this.to, 0);
        this["cont"]();
    }
};

/*==================================================
 *  CopyPasteButton
 *
 *  Adapted from http://spaces.live.com/editorial/rayozzie/demo/liveclip/liveclipsample/techPreview.html.
 *==================================================
 */

/**
 * Creates a button and textarea for displaying structured data and copying it
 * to the clipboard.  The data is dynamically generated by the given 
 * createDataFunction parameter.
 *
 * @param {String} image an image URL to use as the background for the 
 *   generated box
 * @param {Number} width the width in pixels of the generated box
 * @param {Number} height the height in pixels of the generated box
 * @param {Function} createDataFunction a function that is called with no
 *   arguments to generate the structured data
 * @return a new DOM element
 */
SimileAjax.Graphics.createStructuredDataCopyButton = function(image, width, height, createDataFunction) {
    var div = document.createElement("div");
    div.style.position = "relative";
    div.style.display = "inline";
    div.style.width = width + "px";
    div.style.height = height + "px";
    div.style.overflow = "hidden";
    div.style.margin = "2px";
    
    if (SimileAjax.Graphics.pngIsTranslucent) {
        div.style.background = "url(" + image + ") no-repeat";
    } else {
        div.style.filter = "progid:DXImageTransform.Microsoft.AlphaImageLoader(src='" + image +"', sizingMethod='image')";
    }
    
    var style;
    if (SimileAjax.Platform.browser.isIE) {
        style = "filter:alpha(opacity=0)";
    } else {
        style = "opacity: 0";
    }
    div.innerHTML = "<textarea rows='1' autocomplete='off' value='none' style='" + style + "' />";
    
    var textarea = div.firstChild;
    textarea.style.width = width + "px";
    textarea.style.height = height + "px";
    textarea.onmousedown = function(evt) {
        evt = (evt) ? evt : ((event) ? event : null);
        if (evt.button == 2) {
            textarea.value = createDataFunction();
            textarea.select();
        }
    };
    
    return div;
};

SimileAjax.Graphics.getFontRenderingContext = function(elmt, width) {
    return new SimileAjax.Graphics._FontRenderingContext(elmt, width);
};

SimileAjax.Graphics._FontRenderingContext = function(elmt, width) {
    this._elmt = elmt;
    this._elmt.style.visibility = "hidden";
    if (typeof width == "string") {
        this._elmt.style.width = width;
    } else if (typeof width == "number") {
        this._elmt.style.width = width + "px";
    }
};

SimileAjax.Graphics._FontRenderingContext.prototype.dispose = function() {
    this._elmt = null;
};

SimileAjax.Graphics._FontRenderingContext.prototype.update = function() {
    this._elmt.innerHTML = "A";
    this._lineHeight = this._elmt.offsetHeight;
};

SimileAjax.Graphics._FontRenderingContext.prototype.computeSize = function(text) {
    this._elmt.innerHTML = text;
    return {
        width:  this._elmt.offsetWidth,
        height: this._elmt.offsetHeight
    };
};

SimileAjax.Graphics._FontRenderingContext.prototype.getLineHeight = function() {
    return this._lineHeight;
};
