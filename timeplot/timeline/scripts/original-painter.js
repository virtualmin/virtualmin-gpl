/*==================================================
 *  Original Event Painter
 *==================================================
 */

Timeline.OriginalEventPainter = function(params) {
    this._params = params;
    this._onSelectListeners = [];
    
    this._filterMatcher = null;
    this._highlightMatcher = null;
    this._frc = null;
    
    this._eventIdToElmt = {};
};

Timeline.OriginalEventPainter.prototype.initialize = function(band, timeline) {
    this._band = band;
    this._timeline = timeline;
    
    this._backLayer = null;
    this._eventLayer = null;
    this._lineLayer = null;
    this._highlightLayer = null;
    
    this._eventIdToElmt = null;
};

Timeline.OriginalEventPainter.prototype.addOnSelectListener = function(listener) {
    this._onSelectListeners.push(listener);
};

Timeline.OriginalEventPainter.prototype.removeOnSelectListener = function(listener) {
    for (var i = 0; i < this._onSelectListeners.length; i++) {
        if (this._onSelectListeners[i] == listener) {
            this._onSelectListeners.splice(i, 1);
            break;
        }
    }
};

Timeline.OriginalEventPainter.prototype.getFilterMatcher = function() {
    return this._filterMatcher;
};

Timeline.OriginalEventPainter.prototype.setFilterMatcher = function(filterMatcher) {
    this._filterMatcher = filterMatcher;
};

Timeline.OriginalEventPainter.prototype.getHighlightMatcher = function() {
    return this._highlightMatcher;
};

Timeline.OriginalEventPainter.prototype.setHighlightMatcher = function(highlightMatcher) {
    this._highlightMatcher = highlightMatcher;
};

Timeline.OriginalEventPainter.prototype.paint = function() {
    var eventSource = this._band.getEventSource();
    if (eventSource == null) {
        return;
    }
    
    this._eventIdToElmt = {};
    this._prepareForPainting();
    
    var eventTheme = this._params.theme.event;
    var trackHeight = Math.max(eventTheme.track.height, eventTheme.tape.height + this._frc.getLineHeight());
    var metrics = {
        trackOffset:    eventTheme.track.gap,
        trackHeight:    trackHeight,
        trackGap:       eventTheme.track.gap,
        trackIncrement: trackHeight + eventTheme.track.gap,
        icon:           eventTheme.instant.icon,
        iconWidth:      eventTheme.instant.iconWidth,
        iconHeight:     eventTheme.instant.iconHeight,
        labelWidth:     eventTheme.label.width
    }
    
    var minDate = this._band.getMinDate();
    var maxDate = this._band.getMaxDate();
    
    var filterMatcher = (this._filterMatcher != null) ? 
        this._filterMatcher :
        function(evt) { return true; };
    var highlightMatcher = (this._highlightMatcher != null) ? 
        this._highlightMatcher :
        function(evt) { return -1; };
    
    var iterator = eventSource.getEventReverseIterator(minDate, maxDate);
    while (iterator.hasNext()) {
        var evt = iterator.next();
        if (filterMatcher(evt)) {
            this.paintEvent(evt, metrics, this._params.theme, highlightMatcher(evt));
        }
    }
    
    this._highlightLayer.style.display = "block";
    this._lineLayer.style.display = "block";
    this._eventLayer.style.display = "block";
};

Timeline.OriginalEventPainter.prototype.softPaint = function() {
};

Timeline.OriginalEventPainter.prototype._prepareForPainting = function() {
    var band = this._band;
        
    if (this._backLayer == null) {
        this._backLayer = this._band.createLayerDiv(0, "timeline-band-events");
        this._backLayer.style.visibility = "hidden";
        
        var eventLabelPrototype = document.createElement("div");
        eventLabelPrototype.className = "timeline-event-label";
        this._backLayer.appendChild(eventLabelPrototype);
        this._frc = SimileAjax.Graphics.getFontRenderingContext(eventLabelPrototype);
    }
    this._frc.update();
    this._tracks = [];
    
    if (this._highlightLayer != null) {
        band.removeLayerDiv(this._highlightLayer);
    }
    this._highlightLayer = band.createLayerDiv(105, "timeline-band-highlights");
    this._highlightLayer.style.display = "none";
    
    if (this._lineLayer != null) {
        band.removeLayerDiv(this._lineLayer);
    }
    this._lineLayer = band.createLayerDiv(110, "timeline-band-lines");
    this._lineLayer.style.display = "none";
    
    if (this._eventLayer != null) {
        band.removeLayerDiv(this._eventLayer);
    }
    this._eventLayer = band.createLayerDiv(115, "timeline-band-events");
    this._eventLayer.style.display = "none";
};

Timeline.OriginalEventPainter.prototype.paintEvent = function(evt, metrics, theme, highlightIndex) {
    if (evt.isInstant()) {
        this.paintInstantEvent(evt, metrics, theme, highlightIndex);
    } else {
        this.paintDurationEvent(evt, metrics, theme, highlightIndex);
    }
};
    
Timeline.OriginalEventPainter.prototype.paintInstantEvent = function(evt, metrics, theme, highlightIndex) {
    if (evt.isImprecise()) {
        this.paintImpreciseInstantEvent(evt, metrics, theme, highlightIndex);
    } else {
        this.paintPreciseInstantEvent(evt, metrics, theme, highlightIndex);
    }
}

Timeline.OriginalEventPainter.prototype.paintDurationEvent = function(evt, metrics, theme, highlightIndex) {
    if (evt.isImprecise()) {
        this.paintImpreciseDurationEvent(evt, metrics, theme, highlightIndex);
    } else {
        this.paintPreciseDurationEvent(evt, metrics, theme, highlightIndex);
    }
}
    
Timeline.OriginalEventPainter.prototype.paintPreciseInstantEvent = function(evt, metrics, theme, highlightIndex) {
    var doc = this._timeline.getDocument();
    var text = evt.getText();
    
    var startDate = evt.getStart();
    var startPixel = Math.round(this._band.dateToPixelOffset(startDate));
    var iconRightEdge = Math.round(startPixel + metrics.iconWidth / 2);
    var iconLeftEdge = Math.round(startPixel - metrics.iconWidth / 2);
    
    var labelSize = this._frc.computeSize(text);
    var labelLeft = iconRightEdge + theme.event.label.offsetFromLine;
    var labelRight = labelLeft + labelSize.width;
    
    var rightEdge = labelRight;
    var track = this._findFreeTrack(rightEdge);
    
    var labelTop = Math.round(
        metrics.trackOffset + track * metrics.trackIncrement + 
        metrics.trackHeight / 2 - labelSize.height / 2);
        
    var iconElmtData = this._paintEventIcon(evt, track, iconLeftEdge, metrics, theme);
    var labelElmtData = this._paintEventLabel(evt, text, labelLeft, labelTop, labelSize.width, labelSize.height, theme);

    var self = this;
    var clickHandler = function(elmt, domEvt, target) {
        return self._onClickInstantEvent(iconElmtData.elmt, domEvt, evt);
    };
    SimileAjax.DOM.registerEvent(iconElmtData.elmt, "mousedown", clickHandler);
    SimileAjax.DOM.registerEvent(labelElmtData.elmt, "mousedown", clickHandler);
    
    this._createHighlightDiv(highlightIndex, iconElmtData, theme);
    
    this._eventIdToElmt[evt.getID()] = iconElmtData.elmt;
    this._tracks[track] = iconLeftEdge;
};

Timeline.OriginalEventPainter.prototype.paintImpreciseInstantEvent = function(evt, metrics, theme, highlightIndex) {
    var doc = this._timeline.getDocument();
    var text = evt.getText();
    
    var startDate = evt.getStart();
    var endDate = evt.getEnd();
    var startPixel = Math.round(this._band.dateToPixelOffset(startDate));
    var endPixel = Math.round(this._band.dateToPixelOffset(endDate));
    
    var iconRightEdge = Math.round(startPixel + metrics.iconWidth / 2);
    var iconLeftEdge = Math.round(startPixel - metrics.iconWidth / 2);
    
    var labelSize = this._frc.computeSize(text);
    var labelLeft = iconRightEdge + theme.event.label.offsetFromLine;
    var labelRight = labelLeft + labelSize.width;
    
    var rightEdge = Math.max(labelRight, endPixel);
    var track = this._findFreeTrack(rightEdge);
    var labelTop = Math.round(
        metrics.trackOffset + track * metrics.trackIncrement + 
        metrics.trackHeight / 2 - labelSize.height / 2);
    
    var iconElmtData = this._paintEventIcon(evt, track, iconLeftEdge, metrics, theme);
    var labelElmtData = this._paintEventLabel(evt, text, labelLeft, labelTop, labelSize.width, labelSize.height, theme);
    var tapeElmtData = this._paintEventTape(evt, track, startPixel, endPixel, 
        theme.event.instant.impreciseColor, theme.event.instant.impreciseOpacity, metrics, theme);
    
    var self = this;
    var clickHandler = function(elmt, domEvt, target) {
        return self._onClickInstantEvent(iconElmtData.elmt, domEvt, evt);
    };
    SimileAjax.DOM.registerEvent(iconElmtData.elmt, "mousedown", clickHandler);
    SimileAjax.DOM.registerEvent(tapeElmtData.elmt, "mousedown", clickHandler);
    SimileAjax.DOM.registerEvent(labelElmtData.elmt, "mousedown", clickHandler);
    
    this._createHighlightDiv(highlightIndex, iconElmtData, theme);
    
    this._eventIdToElmt[evt.getID()] = iconElmtData.elmt;
    this._tracks[track] = iconLeftEdge;
};

Timeline.OriginalEventPainter.prototype.paintPreciseDurationEvent = function(evt, metrics, theme, highlightIndex) {
    var doc = this._timeline.getDocument();
    var text = evt.getText();
    
    var startDate = evt.getStart();
    var endDate = evt.getEnd();
    var startPixel = Math.round(this._band.dateToPixelOffset(startDate));
    var endPixel = Math.round(this._band.dateToPixelOffset(endDate));
    
    var labelSize = this._frc.computeSize(text);
    var labelLeft = startPixel;
    var labelRight = labelLeft + labelSize.width;
    
    var rightEdge = Math.max(labelRight, endPixel);
    var track = this._findFreeTrack(rightEdge);
    var labelTop = Math.round(
        metrics.trackOffset + track * metrics.trackIncrement + theme.event.tape.height);
    
    var color = evt.getColor();
    color = color != null ? color : theme.event.duration.color;
    
    var tapeElmtData = this._paintEventTape(evt, track, startPixel, endPixel, color, 100, metrics, theme);
    var labelElmtData = this._paintEventLabel(evt, text, labelLeft, labelTop, labelSize.width, labelSize.height, theme);
    
    var self = this;
    var clickHandler = function(elmt, domEvt, target) {
        return self._onClickInstantEvent(tapeElmtData.elmt, domEvt, evt);
    };
    SimileAjax.DOM.registerEvent(tapeElmtData.elmt, "mousedown", clickHandler);
    SimileAjax.DOM.registerEvent(labelElmtData.elmt, "mousedown", clickHandler);
    
    this._createHighlightDiv(highlightIndex, tapeElmtData, theme);
    
    this._eventIdToElmt[evt.getID()] = tapeElmtData.elmt;
    this._tracks[track] = startPixel;
};

Timeline.OriginalEventPainter.prototype.paintImpreciseDurationEvent = function(evt, metrics, theme, highlightIndex) {
    var doc = this._timeline.getDocument();
    var text = evt.getText();
    
    var startDate = evt.getStart();
    var latestStartDate = evt.getLatestStart();
    var endDate = evt.getEnd();
    var earliestEndDate = evt.getEarliestEnd();
    
    var startPixel = Math.round(this._band.dateToPixelOffset(startDate));
    var latestStartPixel = Math.round(this._band.dateToPixelOffset(latestStartDate));
    var endPixel = Math.round(this._band.dateToPixelOffset(endDate));
    var earliestEndPixel = Math.round(this._band.dateToPixelOffset(earliestEndDate));
    
    var labelSize = this._frc.computeSize(text);
    var labelLeft = latestStartPixel;
    var labelRight = labelLeft + labelSize.width;
    
    var rightEdge = Math.max(labelRight, endPixel);
    var track = this._findFreeTrack(rightEdge);
    var labelTop = Math.round(
        metrics.trackOffset + track * metrics.trackIncrement + theme.event.tape.height);
    
    var color = evt.getColor();
    color = color != null ? color : theme.event.duration.color;
    
    var impreciseTapeElmtData = this._paintEventTape(evt, tapeTrack, startPixel, endPixel, 
        theme.event.duration.impreciseColor, theme.event.duration.impreciseOpacity, metrics, theme);
    var tapeElmtData = this._paintEventTape(evt, track, latestStartPixel, earliestEndPixel, color, 100, metrics, theme);
    
    var labelElmtData = this._paintEventLabel(evt, text, labelLeft, labelTop, labelSize.width, labelSize.height, theme);
    
    var self = this;
    var clickHandler = function(elmt, domEvt, target) {
        return self._onClickInstantEvent(tapeElmtData.elmt, domEvt, evt);
    };
    SimileAjax.DOM.registerEvent(tapeElmtData.elmt, "mousedown", clickHandler);
    SimileAjax.DOM.registerEvent(labelElmtData.elmt, "mousedown", clickHandler);
    
    this._createHighlightDiv(highlightIndex, tapeElmtData, theme);
    
    this._eventIdToElmt[evt.getID()] = tapeElmtData.elmt;
    this._tracks[track] = startPixel;
};

Timeline.OriginalEventPainter.prototype._findFreeTrack = function(rightEdge) {
    for (var i = 0; i < this._tracks.length; i++) {
        var t = this._tracks[i];
        if (t > rightEdge) {
            break;
        }
    }
    return i;
};

Timeline.OriginalEventPainter.prototype._paintEventIcon = function(evt, iconTrack, left, metrics, theme) {
    var icon = evt.getIcon();
    icon = icon != null ? icon : metrics.icon;
    
    var middle = metrics.trackOffset + iconTrack * metrics.trackIncrement + metrics.trackHeight / 2;
    var top = Math.round(middle - metrics.iconHeight / 2);

    var img = SimileAjax.Graphics.createTranslucentImage(icon);
    var iconDiv = this._timeline.getDocument().createElement("div");
    iconDiv.style.position = "absolute";
    iconDiv.style.left = left + "px";
    iconDiv.style.top = top + "px";
    iconDiv.appendChild(img);
    iconDiv.style.cursor = "pointer";
    this._eventLayer.appendChild(iconDiv);
    
    return {
        left:   left,
        top:    top,
        width:  metrics.iconWidth,
        height: metrics.iconHeight,
        elmt:   iconDiv
    };
};

Timeline.OriginalEventPainter.prototype._paintEventLabel = function(evt, text, left, top, width, height, theme) {
    var doc = this._timeline.getDocument();
    
    var labelDiv = doc.createElement("div");
    labelDiv.style.position = "absolute";
    labelDiv.style.left = left + "px";
    labelDiv.style.width = width + "px";
    labelDiv.style.top = top + "px";
    labelDiv.innerHTML = text;
    labelDiv.style.cursor = "pointer";
    
    var color = evt.getTextColor();
    if (color == null) {
        color = evt.getColor();
    }
    if (color != null) {
        labelDiv.style.color = color;
    }
    
    this._eventLayer.appendChild(labelDiv);
    
    return {
        left:   left,
        top:    top,
        width:  width,
        height: height,
        elmt:   labelDiv
    };
};

Timeline.OriginalEventPainter.prototype._paintEventTape = function(
    evt, iconTrack, startPixel, endPixel, color, opacity, metrics, theme) {
    
    var tapeWidth = endPixel - startPixel;
    var tapeHeight = theme.event.tape.height;
    var top = metrics.trackOffset + iconTrack * metrics.trackIncrement;
    
    var tapeDiv = this._timeline.getDocument().createElement("div");
    tapeDiv.style.position = "absolute";
    tapeDiv.style.left = startPixel + "px";
    tapeDiv.style.width = tapeWidth + "px";
    tapeDiv.style.top = top + "px";
    tapeDiv.style.height = tapeHeight + "px";
    tapeDiv.style.backgroundColor = color;
    tapeDiv.style.overflow = "hidden";
    tapeDiv.style.cursor = "pointer";
    SimileAjax.Graphics.setOpacity(tapeDiv, opacity);
    
    this._eventLayer.appendChild(tapeDiv);
    
    return {
        left:   startPixel,
        top:    top,
        width:  tapeWidth,
        height: tapeHeight,
        elmt:   tapeDiv
    };
}

Timeline.OriginalEventPainter.prototype._createHighlightDiv = function(highlightIndex, dimensions, theme) {
    if (highlightIndex >= 0) {
        var doc = this._timeline.getDocument();
        var eventTheme = theme.event;
        
        var color = eventTheme.highlightColors[Math.min(highlightIndex, eventTheme.highlightColors.length - 1)];
        
        var div = doc.createElement("div");
        div.style.position = "absolute";
        div.style.overflow = "hidden";
        div.style.left =    (dimensions.left - 2) + "px";
        div.style.width =   (dimensions.width + 4) + "px";
        div.style.top =     (dimensions.top - 2) + "px";
        div.style.height =  (dimensions.height + 4) + "px";
        div.style.background = color;
        
        this._highlightLayer.appendChild(div);
    }
};

Timeline.OriginalEventPainter.prototype._onClickInstantEvent = function(icon, domEvt, evt) {
    var c = SimileAjax.DOM.getPageCoordinates(icon);
    this._showBubble(
        c.left + Math.ceil(icon.offsetWidth / 2), 
        c.top + Math.ceil(icon.offsetHeight / 2),
        evt
    );
    this._fireOnSelect(evt.getID());
    
    domEvt.cancelBubble = true;
    SimileAjax.DOM.cancelEvent(domEvt);
    return false;
};

Timeline.OriginalEventPainter.prototype._onClickDurationEvent = function(target, domEvt, evt) {
    if ("pageX" in domEvt) {
        var x = domEvt.pageX;
        var y = domEvt.pageY;
    } else {
        var c = SimileAjax.DOM.getPageCoordinates(target);
        var x = domEvt.offsetX + c.left;
        var y = domEvt.offsetY + c.top;
    }
    this._showBubble(x, y, evt);
    this._fireOnSelect(evt.getID());
    
    domEvt.cancelBubble = true;
    SimileAjax.DOM.cancelEvent(domEvt);
    return false;
};

Timeline.OriginalEventPainter.prototype.showBubble = function(evt) {
    var elmt = this._eventIdToElmt[evt.getID()];
    if (elmt) {
        var c = SimileAjax.DOM.getPageCoordinates(elmt);
        this._showBubble(c.left + elmt.offsetWidth / 2, c.top + elmt.offsetHeight / 2, evt);
    }
};

Timeline.OriginalEventPainter.prototype._showBubble = function(x, y, evt) {
    var div = document.createElement("div");
    evt.fillInfoBubble(div, this._params.theme, this._band.getLabeller());
    
    SimileAjax.WindowManager.cancelPopups();
    SimileAjax.Graphics.createBubbleForContentAndPoint(div, x, y, this._params.theme.event.bubble.width);
};

Timeline.OriginalEventPainter.prototype._fireOnSelect = function(eventID) {
    for (var i = 0; i < this._onSelectListeners.length; i++) {
        this._onSelectListeners[i](eventID);
    }
};
