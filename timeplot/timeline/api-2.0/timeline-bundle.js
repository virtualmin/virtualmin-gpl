

/* decorators.js */



Timeline.SpanHighlightDecorator=function(params){
this._unit=("unit"in params)?params.unit:SimileAjax.NativeDateUnit;
this._startDate=(typeof params.startDate=="string")?
this._unit.parseFromObject(params.startDate):params.startDate;
this._endDate=(typeof params.endDate=="string")?
this._unit.parseFromObject(params.endDate):params.endDate;
this._startLabel=params.startLabel;
this._endLabel=params.endLabel;
this._color=params.color;
this._opacity=("opacity"in params)?params.opacity:100;
};

Timeline.SpanHighlightDecorator.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._layerDiv=null;
};

Timeline.SpanHighlightDecorator.prototype.paint=function(){
if(this._layerDiv!=null){
this._band.removeLayerDiv(this._layerDiv);
}
this._layerDiv=this._band.createLayerDiv(10);
this._layerDiv.setAttribute("name","span-highlight-decorator");
this._layerDiv.style.display="none";

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

if(this._unit.compare(this._startDate,maxDate)<0&&
this._unit.compare(this._endDate,minDate)>0){

minDate=this._unit.later(minDate,this._startDate);
maxDate=this._unit.earlier(maxDate,this._endDate);

var minPixel=this._band.dateToPixelOffset(minDate);
var maxPixel=this._band.dateToPixelOffset(maxDate);

var doc=this._timeline.getDocument();

var createTable=function(){
var table=doc.createElement("table");
table.insertRow(0).insertCell(0);
return table;
};

var div=doc.createElement("div");
div.style.position="absolute";
div.style.overflow="hidden";
div.style.background=this._color;
if(this._opacity<100){
SimileAjax.Graphics.setOpacity(div,this._opacity);
}
this._layerDiv.appendChild(div);

var tableStartLabel=createTable();
tableStartLabel.style.position="absolute";
tableStartLabel.style.overflow="hidden";
tableStartLabel.style.fontSize="200%";
tableStartLabel.style.fontWeight="bold";
tableStartLabel.style.color=this._color;
tableStartLabel.rows[0].cells[0].innerHTML=this._startLabel;
this._layerDiv.appendChild(tableStartLabel);

var tableEndLabel=createTable();
tableEndLabel.style.position="absolute";
tableEndLabel.style.overflow="hidden";
tableEndLabel.style.fontSize="200%";
tableEndLabel.style.fontWeight="bold";
tableEndLabel.style.color=this._color;
tableEndLabel.rows[0].cells[0].innerHTML=this._endLabel;
this._layerDiv.appendChild(tableEndLabel);

if(this._timeline.isHorizontal()){
div.style.left=minPixel+"px";
div.style.width=(maxPixel-minPixel)+"px";
div.style.top="0px";
div.style.height="100%";

tableStartLabel.style.right=(this._band.getTotalViewLength()-minPixel)+"px";
tableStartLabel.style.width=(this._startLabel.length)+"em";
tableStartLabel.style.top="0px";
tableStartLabel.style.height="100%";
tableStartLabel.style.textAlign="right";
tableStartLabel.rows[0].style.verticalAlign="top";

tableEndLabel.style.left=maxPixel+"px";
tableEndLabel.style.width=(this._endLabel.length)+"em";
tableEndLabel.style.top="0px";
tableEndLabel.style.height="100%";
tableEndLabel.rows[0].style.verticalAlign="top";
}else{
div.style.top=minPixel+"px";
div.style.height=(maxPixel-minPixel)+"px";
div.style.left="0px";
div.style.width="100%";

tableStartLabel.style.bottom=minPixel+"px";
tableStartLabel.style.height="1.5px";
tableStartLabel.style.left="0px";
tableStartLabel.style.width="100%";

tableEndLabel.style.top=maxPixel+"px";
tableEndLabel.style.height="1.5px";
tableEndLabel.style.left="0px";
tableEndLabel.style.width="100%";
}
}
this._layerDiv.style.display="block";
};

Timeline.SpanHighlightDecorator.prototype.softPaint=function(){
};



Timeline.PointHighlightDecorator=function(params){
this._unit=("unit"in params)?params.unit:SimileAjax.NativeDateUnit;
this._date=(typeof params.date=="string")?
this._unit.parseFromObject(params.date):params.date;
this._width=("width"in params)?params.width:10;
this._color=params.color;
this._opacity=("opacity"in params)?params.opacity:100;
};

Timeline.PointHighlightDecorator.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._layerDiv=null;
};

Timeline.PointHighlightDecorator.prototype.paint=function(){
if(this._layerDiv!=null){
this._band.removeLayerDiv(this._layerDiv);
}
this._layerDiv=this._band.createLayerDiv(10);
this._layerDiv.setAttribute("name","span-highlight-decorator");
this._layerDiv.style.display="none";

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

if(this._unit.compare(this._date,maxDate)<0&&
this._unit.compare(this._date,minDate)>0){

var pixel=this._band.dateToPixelOffset(this._date);
var minPixel=pixel-Math.round(this._width/2);

var doc=this._timeline.getDocument();

var div=doc.createElement("div");
div.style.position="absolute";
div.style.overflow="hidden";
div.style.background=this._color;
if(this._opacity<100){
SimileAjax.Graphics.setOpacity(div,this._opacity);
}
this._layerDiv.appendChild(div);

if(this._timeline.isHorizontal()){
div.style.left=minPixel+"px";
div.style.width=this._width+"px";
div.style.top="0px";
div.style.height="100%";
}else{
div.style.top=minPixel+"px";
div.style.height=this._width+"px";
div.style.left="0px";
div.style.width="100%";
}
}
this._layerDiv.style.display="block";
};

Timeline.PointHighlightDecorator.prototype.softPaint=function(){
};


/* detailed-painter.js */



Timeline.DetailedEventPainter=function(params){
this._params=params;
this._onSelectListeners=[];

this._filterMatcher=null;
this._highlightMatcher=null;
this._frc=null;

this._eventIdToElmt={};
};

Timeline.DetailedEventPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backLayer=null;
this._eventLayer=null;
this._lineLayer=null;
this._highlightLayer=null;

this._eventIdToElmt=null;
};

Timeline.DetailedEventPainter.prototype.addOnSelectListener=function(listener){
this._onSelectListeners.push(listener);
};

Timeline.DetailedEventPainter.prototype.removeOnSelectListener=function(listener){
for(var i=0;i<this._onSelectListeners.length;i++){
if(this._onSelectListeners[i]==listener){
this._onSelectListeners.splice(i,1);
break;
}
}
};

Timeline.DetailedEventPainter.prototype.getFilterMatcher=function(){
return this._filterMatcher;
};

Timeline.DetailedEventPainter.prototype.setFilterMatcher=function(filterMatcher){
this._filterMatcher=filterMatcher;
};

Timeline.DetailedEventPainter.prototype.getHighlightMatcher=function(){
return this._highlightMatcher;
};

Timeline.DetailedEventPainter.prototype.setHighlightMatcher=function(highlightMatcher){
this._highlightMatcher=highlightMatcher;
};

Timeline.DetailedEventPainter.prototype.paint=function(){
var eventSource=this._band.getEventSource();
if(eventSource==null){
return;
}

this._eventIdToElmt={};
this._prepareForPainting();

var eventTheme=this._params.theme.event;
var trackHeight=Math.max(eventTheme.track.height,this._frc.getLineHeight());
var metrics={
trackOffset:Math.round(this._band.getViewWidth()/2-trackHeight/2),
trackHeight:trackHeight,
trackGap:eventTheme.track.gap,
trackIncrement:trackHeight+eventTheme.track.gap,
icon:eventTheme.instant.icon,
iconWidth:eventTheme.instant.iconWidth,
iconHeight:eventTheme.instant.iconHeight,
labelWidth:eventTheme.label.width
}

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

var filterMatcher=(this._filterMatcher!=null)?
this._filterMatcher:
function(evt){return true;};
var highlightMatcher=(this._highlightMatcher!=null)?
this._highlightMatcher:
function(evt){return-1;};

var iterator=eventSource.getEventReverseIterator(minDate,maxDate);
while(iterator.hasNext()){
var evt=iterator.next();
if(filterMatcher(evt)){
this.paintEvent(evt,metrics,this._params.theme,highlightMatcher(evt));
}
}

this._highlightLayer.style.display="block";
this._lineLayer.style.display="block";
this._eventLayer.style.display="block";
};

Timeline.DetailedEventPainter.prototype.softPaint=function(){
};

Timeline.DetailedEventPainter.prototype._prepareForPainting=function(){
var band=this._band;

if(this._backLayer==null){
this._backLayer=this._band.createLayerDiv(0,"timeline-band-events");
this._backLayer.style.visibility="hidden";

var eventLabelPrototype=document.createElement("span");
eventLabelPrototype.className="timeline-event-label";
this._backLayer.appendChild(eventLabelPrototype);
this._frc=SimileAjax.Graphics.getFontRenderingContext(eventLabelPrototype);
}
this._frc.update();
this._lowerTracks=[];
this._upperTracks=[];

if(this._highlightLayer!=null){
band.removeLayerDiv(this._highlightLayer);
}
this._highlightLayer=band.createLayerDiv(105,"timeline-band-highlights");
this._highlightLayer.style.display="none";

if(this._lineLayer!=null){
band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=band.createLayerDiv(110,"timeline-band-lines");
this._lineLayer.style.display="none";

if(this._eventLayer!=null){
band.removeLayerDiv(this._eventLayer);
}
this._eventLayer=band.createLayerDiv(110,"timeline-band-events");
this._eventLayer.style.display="none";
};

Timeline.DetailedEventPainter.prototype.paintEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isInstant()){
this.paintInstantEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintDurationEvent(evt,metrics,theme,highlightIndex);
}
};

Timeline.DetailedEventPainter.prototype.paintInstantEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isImprecise()){
this.paintImpreciseInstantEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintPreciseInstantEvent(evt,metrics,theme,highlightIndex);
}
}

Timeline.DetailedEventPainter.prototype.paintDurationEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isImprecise()){
this.paintImpreciseDurationEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintPreciseDurationEvent(evt,metrics,theme,highlightIndex);
}
}

Timeline.DetailedEventPainter.prototype.paintPreciseInstantEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var iconRightEdge=Math.round(startPixel+metrics.iconWidth/2);
var iconLeftEdge=Math.round(startPixel-metrics.iconWidth/2);

var labelSize=this._frc.computeSize(text);
var iconTrack=this._findFreeTrackForSolid(iconRightEdge,startPixel);
var iconElmtData=this._paintEventIcon(evt,iconTrack,iconLeftEdge,metrics,theme);

var labelLeft=iconRightEdge+theme.event.label.offsetFromLine;
var labelTrack=iconTrack;

var iconTrackData=this._getTrackData(iconTrack);
if(Math.min(iconTrackData.solid,iconTrackData.text)>=labelLeft+labelSize.width){
iconTrackData.solid=iconLeftEdge;
iconTrackData.text=labelLeft;
}else{
iconTrackData.solid=iconLeftEdge;

labelLeft=startPixel+theme.event.label.offsetFromLine;
labelTrack=this._findFreeTrackForText(iconTrack,labelLeft+labelSize.width,function(t){t.line=startPixel-2;});
this._getTrackData(labelTrack).text=iconLeftEdge;

this._paintEventLine(evt,startPixel,iconTrack,labelTrack,metrics,theme);
}

var labelTop=Math.round(
metrics.trackOffset+labelTrack*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(iconElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(iconElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,iconElmtData,theme);

this._eventIdToElmt[evt.getID()]=iconElmtData.elmt;
};

Timeline.DetailedEventPainter.prototype.paintImpreciseInstantEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var endDate=evt.getEnd();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));

var iconRightEdge=Math.round(startPixel+metrics.iconWidth/2);
var iconLeftEdge=Math.round(startPixel-metrics.iconWidth/2);

var labelSize=this._frc.computeSize(text);
var iconTrack=this._findFreeTrackForSolid(endPixel,startPixel);

var tapeElmtData=this._paintEventTape(evt,iconTrack,startPixel,endPixel,
theme.event.instant.impreciseColor,theme.event.instant.impreciseOpacity,metrics,theme);
var iconElmtData=this._paintEventIcon(evt,iconTrack,iconLeftEdge,metrics,theme);

var iconTrackData=this._getTrackData(iconTrack);
iconTrackData.solid=iconLeftEdge;

var labelLeft=iconRightEdge+theme.event.label.offsetFromLine;
var labelRight=labelLeft+labelSize.width;
var labelTrack;
if(labelRight<endPixel){
labelTrack=iconTrack;
}else{
labelLeft=startPixel+theme.event.label.offsetFromLine;
labelRight=labelLeft+labelSize.width;

labelTrack=this._findFreeTrackForText(iconTrack,labelRight,function(t){t.line=startPixel-2;});
this._getTrackData(labelTrack).text=iconLeftEdge;

this._paintEventLine(evt,startPixel,iconTrack,labelTrack,metrics,theme);
}
var labelTop=Math.round(
metrics.trackOffset+labelTrack*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(iconElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(iconElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,iconElmtData,theme);

this._eventIdToElmt[evt.getID()]=iconElmtData.elmt;
};

Timeline.DetailedEventPainter.prototype.paintPreciseDurationEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var endDate=evt.getEnd();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));

var labelSize=this._frc.computeSize(text);
var tapeTrack=this._findFreeTrackForSolid(endPixel);
var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var tapeElmtData=this._paintEventTape(evt,tapeTrack,startPixel,endPixel,color,100,metrics,theme);

var tapeTrackData=this._getTrackData(tapeTrack);
tapeTrackData.solid=startPixel;

var labelLeft=startPixel+theme.event.label.offsetFromLine;
var labelTrack=this._findFreeTrackForText(tapeTrack,labelLeft+labelSize.width,function(t){t.line=startPixel-2;});
this._getTrackData(labelTrack).text=startPixel-2;

this._paintEventLine(evt,startPixel,tapeTrack,labelTrack,metrics,theme);

var labelTop=Math.round(
metrics.trackOffset+labelTrack*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickDurationEvent(tapeElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,tapeElmtData,theme);

this._eventIdToElmt[evt.getID()]=tapeElmtData.elmt;
};

Timeline.DetailedEventPainter.prototype.paintImpreciseDurationEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var latestStartDate=evt.getLatestStart();
var endDate=evt.getEnd();
var earliestEndDate=evt.getEarliestEnd();

var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var latestStartPixel=Math.round(this._band.dateToPixelOffset(latestStartDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));
var earliestEndPixel=Math.round(this._band.dateToPixelOffset(earliestEndDate));

var labelSize=this._frc.computeSize(text);
var tapeTrack=this._findFreeTrackForSolid(endPixel);
var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var impreciseTapeElmtData=this._paintEventTape(evt,tapeTrack,startPixel,endPixel,
theme.event.duration.impreciseColor,theme.event.duration.impreciseOpacity,metrics,theme);
var tapeElmtData=this._paintEventTape(evt,tapeTrack,latestStartPixel,earliestEndPixel,color,100,metrics,theme);

var tapeTrackData=this._getTrackData(tapeTrack);
tapeTrackData.solid=startPixel;

var labelLeft=latestStartPixel+theme.event.label.offsetFromLine;
var labelTrack=this._findFreeTrackForText(tapeTrack,labelLeft+labelSize.width,function(t){t.line=latestStartPixel-2;});
this._getTrackData(labelTrack).text=latestStartPixel-2;

this._paintEventLine(evt,latestStartPixel,tapeTrack,labelTrack,metrics,theme);

var labelTop=Math.round(
metrics.trackOffset+labelTrack*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickDurationEvent(tapeElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,tapeElmtData,theme);

this._eventIdToElmt[evt.getID()]=tapeElmtData.elmt;
};

Timeline.DetailedEventPainter.prototype._findFreeTrackForSolid=function(solidEdge,softEdge){
for(var i=0;true;i++){
if(i<this._lowerTracks.length){
var t=this._lowerTracks[i];
if(Math.min(t.solid,t.text)>solidEdge&&(!(softEdge)||t.line>softEdge)){
return i;
}
}else{
this._lowerTracks.push({
solid:Number.POSITIVE_INFINITY,
text:Number.POSITIVE_INFINITY,
line:Number.POSITIVE_INFINITY
});

return i;
}

if(i<this._upperTracks.length){
var t=this._upperTracks[i];
if(Math.min(t.solid,t.text)>solidEdge&&(!(softEdge)||t.line>softEdge)){
return-1-i;
}
}else{
this._upperTracks.push({
solid:Number.POSITIVE_INFINITY,
text:Number.POSITIVE_INFINITY,
line:Number.POSITIVE_INFINITY
});

return-1-i;
}
}
};

Timeline.DetailedEventPainter.prototype._findFreeTrackForText=function(fromTrack,edge,occupiedTrackVisitor){
var extendUp;
var index;
var firstIndex;
var result;

if(fromTrack<0){
extendUp=true;
firstIndex=-fromTrack;

index=this._findFreeUpperTrackForText(firstIndex,edge);
result=-1-index;
}else if(fromTrack>0){
extendUp=false;
firstIndex=fromTrack+1;

index=this._findFreeLowerTrackForText(firstIndex,edge);
result=index;
}else{
var upIndex=this._findFreeUpperTrackForText(0,edge);
var downIndex=this._findFreeLowerTrackForText(1,edge);

if(downIndex-1<=upIndex){
extendUp=false;
firstIndex=1;
index=downIndex;
result=index;
}else{
extendUp=true;
firstIndex=0;
index=upIndex;
result=-1-index;
}
}

if(extendUp){
if(index==this._upperTracks.length){
this._upperTracks.push({
solid:Number.POSITIVE_INFINITY,
text:Number.POSITIVE_INFINITY,
line:Number.POSITIVE_INFINITY
});
}
for(var i=firstIndex;i<index;i++){
occupiedTrackVisitor(this._upperTracks[i]);
}
}else{
if(index==this._lowerTracks.length){
this._lowerTracks.push({
solid:Number.POSITIVE_INFINITY,
text:Number.POSITIVE_INFINITY,
line:Number.POSITIVE_INFINITY
});
}
for(var i=firstIndex;i<index;i++){
occupiedTrackVisitor(this._lowerTracks[i]);
}
}
return result;
};

Timeline.DetailedEventPainter.prototype._findFreeLowerTrackForText=function(index,edge){
for(;index<this._lowerTracks.length;index++){
var t=this._lowerTracks[index];
if(Math.min(t.solid,t.text)>=edge){
break;
}
}
return index;
};

Timeline.DetailedEventPainter.prototype._findFreeUpperTrackForText=function(index,edge){
for(;index<this._upperTracks.length;index++){
var t=this._upperTracks[index];
if(Math.min(t.solid,t.text)>=edge){
break;
}
}
return index;
};

Timeline.DetailedEventPainter.prototype._getTrackData=function(index){
return(index<0)?this._upperTracks[-index-1]:this._lowerTracks[index];
};

Timeline.DetailedEventPainter.prototype._paintEventLine=function(evt,left,startTrack,endTrack,metrics,theme){
var top=Math.round(metrics.trackOffset+startTrack*metrics.trackIncrement+metrics.trackHeight/2);
var height=Math.round(Math.abs(endTrack-startTrack)*metrics.trackIncrement);

var lineStyle="1px solid "+theme.event.label.lineColor;
var lineDiv=this._timeline.getDocument().createElement("div");
lineDiv.style.position="absolute";
lineDiv.style.left=left+"px";
lineDiv.style.width=theme.event.label.offsetFromLine+"px";
lineDiv.style.height=height+"px";
if(startTrack>endTrack){
lineDiv.style.top=(top-height)+"px";
lineDiv.style.borderTop=lineStyle;
}else{
lineDiv.style.top=top+"px";
lineDiv.style.borderBottom=lineStyle;
}
lineDiv.style.borderLeft=lineStyle;
this._lineLayer.appendChild(lineDiv);
};

Timeline.DetailedEventPainter.prototype._paintEventIcon=function(evt,iconTrack,left,metrics,theme){
var icon=evt.getIcon();
icon=icon!=null?icon:metrics.icon;

var middle=metrics.trackOffset+iconTrack*metrics.trackIncrement+metrics.trackHeight/2;
var top=Math.round(middle-metrics.iconHeight/2);

var img=SimileAjax.Graphics.createTranslucentImage(icon);
var iconDiv=this._timeline.getDocument().createElement("div");
iconDiv.style.position="absolute";
iconDiv.style.left=left+"px";
iconDiv.style.top=top+"px";
iconDiv.appendChild(img);
iconDiv.style.cursor="pointer";
this._eventLayer.appendChild(iconDiv);

return{
left:left,
top:top,
width:metrics.iconWidth,
height:metrics.iconHeight,
elmt:iconDiv
};
};

Timeline.DetailedEventPainter.prototype._paintEventLabel=function(evt,text,left,top,width,height,theme){
var doc=this._timeline.getDocument();

var labelBackgroundDiv=doc.createElement("div");
labelBackgroundDiv.style.position="absolute";
labelBackgroundDiv.style.left=left+"px";
labelBackgroundDiv.style.width=width+"px";
labelBackgroundDiv.style.top=top+"px";
labelBackgroundDiv.style.height=height+"px";
labelBackgroundDiv.style.backgroundColor=theme.event.label.backgroundColor;
SimileAjax.Graphics.setOpacity(labelBackgroundDiv,theme.event.label.backgroundOpacity);
this._eventLayer.appendChild(labelBackgroundDiv);

var labelDiv=doc.createElement("div");
labelDiv.style.position="absolute";
labelDiv.style.left=left+"px";
labelDiv.style.width=width+"px";
labelDiv.style.top=top+"px";
labelDiv.innerHTML=text;
labelDiv.style.cursor="pointer";

var color=evt.getTextColor();
if(color==null){
color=evt.getColor();
}
if(color!=null){
labelDiv.style.color=color;
}

this._eventLayer.appendChild(labelDiv);

return{
left:left,
top:top,
width:width,
height:height,
elmt:labelDiv
};
};

Timeline.DetailedEventPainter.prototype._paintEventTape=function(
evt,iconTrack,startPixel,endPixel,color,opacity,metrics,theme){

var tapeWidth=endPixel-startPixel;
var tapeHeight=theme.event.tape.height;
var middle=metrics.trackOffset+iconTrack*metrics.trackIncrement+metrics.trackHeight/2;
var top=Math.round(middle-tapeHeight/2);

var tapeDiv=this._timeline.getDocument().createElement("div");
tapeDiv.style.position="absolute";
tapeDiv.style.left=startPixel+"px";
tapeDiv.style.width=tapeWidth+"px";
tapeDiv.style.top=top+"px";
tapeDiv.style.height=tapeHeight+"px";
tapeDiv.style.backgroundColor=color;
tapeDiv.style.overflow="hidden";
tapeDiv.style.cursor="pointer";
SimileAjax.Graphics.setOpacity(tapeDiv,opacity);

this._eventLayer.appendChild(tapeDiv);

return{
left:startPixel,
top:top,
width:tapeWidth,
height:tapeHeight,
elmt:tapeDiv
};
}

Timeline.DetailedEventPainter.prototype._createHighlightDiv=function(highlightIndex,dimensions,theme){
if(highlightIndex>=0){
var doc=this._timeline.getDocument();
var eventTheme=theme.event;

var color=eventTheme.highlightColors[Math.min(highlightIndex,eventTheme.highlightColors.length-1)];

var div=doc.createElement("div");
div.style.position="absolute";
div.style.overflow="hidden";
div.style.left=(dimensions.left-2)+"px";
div.style.width=(dimensions.width+4)+"px";
div.style.top=(dimensions.top-2)+"px";
div.style.height=(dimensions.height+4)+"px";
div.style.background=color;

this._highlightLayer.appendChild(div);
}
};

Timeline.DetailedEventPainter.prototype._onClickInstantEvent=function(icon,domEvt,evt){
var c=SimileAjax.DOM.getPageCoordinates(icon);
this._showBubble(
c.left+Math.ceil(icon.offsetWidth/2),
c.top+Math.ceil(icon.offsetHeight/2),
evt
);
this._fireOnSelect(evt.getID());

domEvt.cancelBubble=true;
SimileAjax.DOM.cancelEvent(domEvt);
return false;
};

Timeline.DetailedEventPainter.prototype._onClickDurationEvent=function(target,domEvt,evt){
if("pageX"in domEvt){
var x=domEvt.pageX;
var y=domEvt.pageY;
}else{
var c=SimileAjax.DOM.getPageCoordinates(target);
var x=domEvt.offsetX+c.left;
var y=domEvt.offsetY+c.top;
}
this._showBubble(x,y,evt);
this._fireOnSelect(evt.getID());

domEvt.cancelBubble=true;
SimileAjax.DOM.cancelEvent(domEvt);
return false;
};

Timeline.DetailedEventPainter.prototype.showBubble=function(evt){
var elmt=this._eventIdToElmt[evt.getID()];
if(elmt){
var c=SimileAjax.DOM.getPageCoordinates(elmt);
this._showBubble(c.left+elmt.offsetWidth/2,c.top+elmt.offsetHeight/2,evt);
}
};

Timeline.DetailedEventPainter.prototype._showBubble=function(x,y,evt){
var div=document.createElement("div");
evt.fillInfoBubble(div,this._params.theme,this._band.getLabeller());

SimileAjax.WindowManager.cancelPopups();
SimileAjax.Graphics.createBubbleForContentAndPoint(div,x,y,this._params.theme.event.bubble.width);
};

Timeline.DetailedEventPainter.prototype._fireOnSelect=function(eventID){
for(var i=0;i<this._onSelectListeners.length;i++){
this._onSelectListeners[i](eventID);
}
};


/* ether-painters.js */



Timeline.GregorianEtherPainter=function(params){
this._params=params;
this._theme=params.theme;
this._unit=params.unit;
this._multiple=("multiple"in params)?params.multiple:1;
};

Timeline.GregorianEtherPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backgroundLayer=band.createLayerDiv(0);
this._backgroundLayer.setAttribute("name","ether-background");
this._backgroundLayer.style.background=this._theme.ether.backgroundColors[band.getIndex()];

this._markerLayer=null;
this._lineLayer=null;

var align=("align"in this._params&&this._params.align!=undefined)?this._params.align:
this._theme.ether.interval.marker[timeline.isHorizontal()?"hAlign":"vAlign"];
var showLine=("showLine"in this._params)?this._params.showLine:
this._theme.ether.interval.line.show;

this._intervalMarkerLayout=new Timeline.EtherIntervalMarkerLayout(
this._timeline,this._band,this._theme,align,showLine);

this._highlight=new Timeline.EtherHighlight(
this._timeline,this._band,this._theme,this._backgroundLayer);
}

Timeline.GregorianEtherPainter.prototype.setHighlight=function(startDate,endDate){
this._highlight.position(startDate,endDate);
}

Timeline.GregorianEtherPainter.prototype.paint=function(){
if(this._markerLayer){
this._band.removeLayerDiv(this._markerLayer);
}
this._markerLayer=this._band.createLayerDiv(100);
this._markerLayer.setAttribute("name","ether-markers");
this._markerLayer.style.display="none";

if(this._lineLayer){
this._band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=this._band.createLayerDiv(1);
this._lineLayer.setAttribute("name","ether-lines");
this._lineLayer.style.display="none";

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

var timeZone=this._band.getTimeZone();
var labeller=this._band.getLabeller();

SimileAjax.DateTime.roundDownToInterval(minDate,this._unit,timeZone,this._multiple,this._theme.firstDayOfWeek);

var p=this;
var incrementDate=function(date){
for(var i=0;i<p._multiple;i++){
SimileAjax.DateTime.incrementByInterval(date,p._unit);
}
};

while(minDate.getTime()<maxDate.getTime()){
this._intervalMarkerLayout.createIntervalMarker(
minDate,labeller,this._unit,this._markerLayer,this._lineLayer);

incrementDate(minDate);
}
this._markerLayer.style.display="block";
this._lineLayer.style.display="block";
};

Timeline.GregorianEtherPainter.prototype.softPaint=function(){
};



Timeline.HotZoneGregorianEtherPainter=function(params){
this._params=params;
this._theme=params.theme;

this._zones=[{
startTime:Number.NEGATIVE_INFINITY,
endTime:Number.POSITIVE_INFINITY,
unit:params.unit,
multiple:1
}];
for(var i=0;i<params.zones.length;i++){
var zone=params.zones[i];
var zoneStart=SimileAjax.DateTime.parseGregorianDateTime(zone.start).getTime();
var zoneEnd=SimileAjax.DateTime.parseGregorianDateTime(zone.end).getTime();

for(var j=0;j<this._zones.length&&zoneEnd>zoneStart;j++){
var zone2=this._zones[j];

if(zoneStart<zone2.endTime){
if(zoneStart>zone2.startTime){
this._zones.splice(j,0,{
startTime:zone2.startTime,
endTime:zoneStart,
unit:zone2.unit,
multiple:zone2.multiple
});
j++;

zone2.startTime=zoneStart;
}

if(zoneEnd<zone2.endTime){
this._zones.splice(j,0,{
startTime:zoneStart,
endTime:zoneEnd,
unit:zone.unit,
multiple:(zone.multiple)?zone.multiple:1
});
j++;

zone2.startTime=zoneEnd;
zoneStart=zoneEnd;
}else{
zone2.multiple=zone.multiple;
zone2.unit=zone.unit;
zoneStart=zone2.endTime;
}
}
}
}
};

Timeline.HotZoneGregorianEtherPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backgroundLayer=band.createLayerDiv(0);
this._backgroundLayer.setAttribute("name","ether-background");
this._backgroundLayer.style.background=this._theme.ether.backgroundColors[band.getIndex()];

this._markerLayer=null;
this._lineLayer=null;

var align=("align"in this._params&&this._params.align!=undefined)?this._params.align:
this._theme.ether.interval.marker[timeline.isHorizontal()?"hAlign":"vAlign"];
var showLine=("showLine"in this._params)?this._params.showLine:
this._theme.ether.interval.line.show;

this._intervalMarkerLayout=new Timeline.EtherIntervalMarkerLayout(
this._timeline,this._band,this._theme,align,showLine);

this._highlight=new Timeline.EtherHighlight(
this._timeline,this._band,this._theme,this._backgroundLayer);
}

Timeline.HotZoneGregorianEtherPainter.prototype.setHighlight=function(startDate,endDate){
this._highlight.position(startDate,endDate);
}

Timeline.HotZoneGregorianEtherPainter.prototype.paint=function(){
if(this._markerLayer){
this._band.removeLayerDiv(this._markerLayer);
}
this._markerLayer=this._band.createLayerDiv(100);
this._markerLayer.setAttribute("name","ether-markers");
this._markerLayer.style.display="none";

if(this._lineLayer){
this._band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=this._band.createLayerDiv(1);
this._lineLayer.setAttribute("name","ether-lines");
this._lineLayer.style.display="none";

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

var timeZone=this._band.getTimeZone();
var labeller=this._band.getLabeller();

var p=this;
var incrementDate=function(date,zone){
for(var i=0;i<zone.multiple;i++){
SimileAjax.DateTime.incrementByInterval(date,zone.unit);
}
};

var zStart=0;
while(zStart<this._zones.length){
if(minDate.getTime()<this._zones[zStart].endTime){
break;
}
zStart++;
}
var zEnd=this._zones.length-1;
while(zEnd>=0){
if(maxDate.getTime()>this._zones[zEnd].startTime){
break;
}
zEnd--;
}

for(var z=zStart;z<=zEnd;z++){
var zone=this._zones[z];

var minDate2=new Date(Math.max(minDate.getTime(),zone.startTime));
var maxDate2=new Date(Math.min(maxDate.getTime(),zone.endTime));

SimileAjax.DateTime.roundDownToInterval(minDate2,zone.unit,timeZone,zone.multiple,this._theme.firstDayOfWeek);
SimileAjax.DateTime.roundUpToInterval(maxDate2,zone.unit,timeZone,zone.multiple,this._theme.firstDayOfWeek);

while(minDate2.getTime()<maxDate2.getTime()){
this._intervalMarkerLayout.createIntervalMarker(
minDate2,labeller,zone.unit,this._markerLayer,this._lineLayer);

incrementDate(minDate2,zone);
}
}
this._markerLayer.style.display="block";
this._lineLayer.style.display="block";
};

Timeline.HotZoneGregorianEtherPainter.prototype.softPaint=function(){
};



Timeline.YearCountEtherPainter=function(params){
this._params=params;
this._theme=params.theme;
this._startDate=SimileAjax.DateTime.parseGregorianDateTime(params.startDate);
this._multiple=("multiple"in params)?params.multiple:1;
};

Timeline.YearCountEtherPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backgroundLayer=band.createLayerDiv(0);
this._backgroundLayer.setAttribute("name","ether-background");
this._backgroundLayer.style.background=this._theme.ether.backgroundColors[band.getIndex()];

this._markerLayer=null;
this._lineLayer=null;

var align=("align"in this._params)?this._params.align:
this._theme.ether.interval.marker[timeline.isHorizontal()?"hAlign":"vAlign"];
var showLine=("showLine"in this._params)?this._params.showLine:
this._theme.ether.interval.line.show;

this._intervalMarkerLayout=new Timeline.EtherIntervalMarkerLayout(
this._timeline,this._band,this._theme,align,showLine);

this._highlight=new Timeline.EtherHighlight(
this._timeline,this._band,this._theme,this._backgroundLayer);
};

Timeline.YearCountEtherPainter.prototype.setHighlight=function(startDate,endDate){
this._highlight.position(startDate,endDate);
};

Timeline.YearCountEtherPainter.prototype.paint=function(){
if(this._markerLayer){
this._band.removeLayerDiv(this._markerLayer);
}
this._markerLayer=this._band.createLayerDiv(100);
this._markerLayer.setAttribute("name","ether-markers");
this._markerLayer.style.display="none";

if(this._lineLayer){
this._band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=this._band.createLayerDiv(1);
this._lineLayer.setAttribute("name","ether-lines");
this._lineLayer.style.display="none";

var minDate=new Date(this._startDate.getTime());
var maxDate=this._band.getMaxDate();
var yearDiff=this._band.getMinDate().getUTCFullYear()-this._startDate.getUTCFullYear();
minDate.setUTCFullYear(this._band.getMinDate().getUTCFullYear()-yearDiff%this._multiple);

var p=this;
var incrementDate=function(date){
for(var i=0;i<p._multiple;i++){
SimileAjax.DateTime.incrementByInterval(date,SimileAjax.DateTime.YEAR);
}
};
var labeller={
labelInterval:function(date,intervalUnit){
var diff=date.getUTCFullYear()-p._startDate.getUTCFullYear();
return{
text:diff,
emphasized:diff==0
};
}
};

while(minDate.getTime()<maxDate.getTime()){
this._intervalMarkerLayout.createIntervalMarker(
minDate,labeller,SimileAjax.DateTime.YEAR,this._markerLayer,this._lineLayer);

incrementDate(minDate);
}
this._markerLayer.style.display="block";
this._lineLayer.style.display="block";
};

Timeline.YearCountEtherPainter.prototype.softPaint=function(){
};



Timeline.QuarterlyEtherPainter=function(params){
this._params=params;
this._theme=params.theme;
this._startDate=SimileAjax.DateTime.parseGregorianDateTime(params.startDate);
};

Timeline.QuarterlyEtherPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backgroundLayer=band.createLayerDiv(0);
this._backgroundLayer.setAttribute("name","ether-background");
this._backgroundLayer.style.background=this._theme.ether.backgroundColors[band.getIndex()];

this._markerLayer=null;
this._lineLayer=null;

var align=("align"in this._params)?this._params.align:
this._theme.ether.interval.marker[timeline.isHorizontal()?"hAlign":"vAlign"];
var showLine=("showLine"in this._params)?this._params.showLine:
this._theme.ether.interval.line.show;

this._intervalMarkerLayout=new Timeline.EtherIntervalMarkerLayout(
this._timeline,this._band,this._theme,align,showLine);

this._highlight=new Timeline.EtherHighlight(
this._timeline,this._band,this._theme,this._backgroundLayer);
};

Timeline.QuarterlyEtherPainter.prototype.setHighlight=function(startDate,endDate){
this._highlight.position(startDate,endDate);
};

Timeline.QuarterlyEtherPainter.prototype.paint=function(){
if(this._markerLayer){
this._band.removeLayerDiv(this._markerLayer);
}
this._markerLayer=this._band.createLayerDiv(100);
this._markerLayer.setAttribute("name","ether-markers");
this._markerLayer.style.display="none";

if(this._lineLayer){
this._band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=this._band.createLayerDiv(1);
this._lineLayer.setAttribute("name","ether-lines");
this._lineLayer.style.display="none";

var minDate=new Date(0);
var maxDate=this._band.getMaxDate();

minDate.setUTCFullYear(Math.max(this._startDate.getUTCFullYear(),this._band.getMinDate().getUTCFullYear()));
minDate.setUTCMonth(this._startDate.getUTCMonth());

var p=this;
var incrementDate=function(date){
date.setUTCMonth(date.getUTCMonth()+3);
};
var labeller={
labelInterval:function(date,intervalUnit){
var quarters=(4+(date.getUTCMonth()-p._startDate.getUTCMonth())/3)%4;
if(quarters!=0){
return{text:"Q"+(quarters+1),emphasized:false};
}else{
return{text:"Y"+(date.getUTCFullYear()-p._startDate.getUTCFullYear()+1),emphasized:true};
}
}
};

while(minDate.getTime()<maxDate.getTime()){
this._intervalMarkerLayout.createIntervalMarker(
minDate,labeller,SimileAjax.DateTime.YEAR,this._markerLayer,this._lineLayer);

incrementDate(minDate);
}
this._markerLayer.style.display="block";
this._lineLayer.style.display="block";
};

Timeline.QuarterlyEtherPainter.prototype.softPaint=function(){
};



Timeline.EtherIntervalMarkerLayout=function(timeline,band,theme,align,showLine){
var horizontal=timeline.isHorizontal();
if(horizontal){
if(align=="Top"){
this.positionDiv=function(div,offset){
div.style.left=offset+"px";
div.style.top="0px";
};
}else{
this.positionDiv=function(div,offset){
div.style.left=offset+"px";
div.style.bottom="0px";
};
}
}else{
if(align=="Left"){
this.positionDiv=function(div,offset){
div.style.top=offset+"px";
div.style.left="0px";
};
}else{
this.positionDiv=function(div,offset){
div.style.top=offset+"px";
div.style.right="0px";
};
}
}

var markerTheme=theme.ether.interval.marker;
var lineTheme=theme.ether.interval.line;
var weekendTheme=theme.ether.interval.weekend;

var stylePrefix=(horizontal?"h":"v")+align;
var labelStyler=markerTheme[stylePrefix+"Styler"];
var emphasizedLabelStyler=markerTheme[stylePrefix+"EmphasizedStyler"];
var day=SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.DAY];

this.createIntervalMarker=function(date,labeller,unit,markerDiv,lineDiv){
var offset=Math.round(band.dateToPixelOffset(date));

if(showLine&&unit!=SimileAjax.DateTime.WEEK){
var divLine=timeline.getDocument().createElement("div");
divLine.style.position="absolute";

if(lineTheme.opacity<100){
SimileAjax.Graphics.setOpacity(divLine,lineTheme.opacity);
}

if(horizontal){
divLine.style.borderLeft="1px solid "+lineTheme.color;
divLine.style.left=offset+"px";
divLine.style.width="1px";
divLine.style.top="0px";
divLine.style.height="100%";
}else{
divLine.style.borderTop="1px solid "+lineTheme.color;
divLine.style.top=offset+"px";
divLine.style.height="1px";
divLine.style.left="0px";
divLine.style.width="100%";
}
lineDiv.appendChild(divLine);
}
if(unit==SimileAjax.DateTime.WEEK){
var firstDayOfWeek=theme.firstDayOfWeek;

var saturday=new Date(date.getTime()+(6-firstDayOfWeek-7)*day);
var monday=new Date(saturday.getTime()+2*day);

var saturdayPixel=Math.round(band.dateToPixelOffset(saturday));
var mondayPixel=Math.round(band.dateToPixelOffset(monday));
var length=Math.max(1,mondayPixel-saturdayPixel);

var divWeekend=timeline.getDocument().createElement("div");
divWeekend.style.position="absolute";

divWeekend.style.background=weekendTheme.color;
if(weekendTheme.opacity<100){
SimileAjax.Graphics.setOpacity(divWeekend,weekendTheme.opacity);
}

if(horizontal){
divWeekend.style.left=saturdayPixel+"px";
divWeekend.style.width=length+"px";
divWeekend.style.top="0px";
divWeekend.style.height="100%";
}else{
divWeekend.style.top=saturdayPixel+"px";
divWeekend.style.height=length+"px";
divWeekend.style.left="0px";
divWeekend.style.width="100%";
}
lineDiv.appendChild(divWeekend);
}

var label=labeller.labelInterval(date,unit);

var div=timeline.getDocument().createElement("div");
div.innerHTML=label.text;
div.style.position="absolute";
(label.emphasized?emphasizedLabelStyler:labelStyler)(div);

this.positionDiv(div,offset);
markerDiv.appendChild(div);

return div;
};
};



Timeline.EtherHighlight=function(timeline,band,theme,backgroundLayer){
var horizontal=timeline.isHorizontal();

this._highlightDiv=null;
this._createHighlightDiv=function(){
if(this._highlightDiv==null){
this._highlightDiv=timeline.getDocument().createElement("div");
this._highlightDiv.setAttribute("name","ether-highlight");
this._highlightDiv.style.position="absolute";
this._highlightDiv.style.background=theme.ether.highlightColor;

var opacity=theme.ether.highlightOpacity;
if(opacity<100){
SimileAjax.Graphics.setOpacity(this._highlightDiv,opacity);
}

backgroundLayer.appendChild(this._highlightDiv);
}
}

this.position=function(startDate,endDate){
this._createHighlightDiv();

var startPixel=Math.round(band.dateToPixelOffset(startDate));
var endPixel=Math.round(band.dateToPixelOffset(endDate));
var length=Math.max(endPixel-startPixel,3);
if(horizontal){
this._highlightDiv.style.left=startPixel+"px";
this._highlightDiv.style.width=length+"px";
this._highlightDiv.style.top="2px";
this._highlightDiv.style.height=(band.getViewWidth()-4)+"px";
}else{
this._highlightDiv.style.top=startPixel+"px";
this._highlightDiv.style.height=length+"px";
this._highlightDiv.style.left="2px";
this._highlightDiv.style.width=(band.getViewWidth()-4)+"px";
}
}
};



/* ethers.js */



Timeline.LinearEther=function(params){
this._params=params;
this._interval=params.interval;
this._pixelsPerInterval=params.pixelsPerInterval;
};

Timeline.LinearEther.prototype.initialize=function(timeline){
this._timeline=timeline;
this._unit=timeline.getUnit();

if("startsOn"in this._params){
this._start=this._unit.parseFromObject(this._params.startsOn);
}else if("endsOn"in this._params){
this._start=this._unit.parseFromObject(this._params.endsOn);
this.shiftPixels(-this._timeline.getPixelLength());
}else if("centersOn"in this._params){
this._start=this._unit.parseFromObject(this._params.centersOn);
this.shiftPixels(-this._timeline.getPixelLength()/2);
}else{
this._start=this._unit.makeDefaultValue();
this.shiftPixels(-this._timeline.getPixelLength()/2);
}
};

Timeline.LinearEther.prototype.setDate=function(date){
this._start=this._unit.cloneValue(date);
};

Timeline.LinearEther.prototype.shiftPixels=function(pixels){
var numeric=this._interval*pixels/this._pixelsPerInterval;
this._start=this._unit.change(this._start,numeric);
};

Timeline.LinearEther.prototype.dateToPixelOffset=function(date){
var numeric=this._unit.compare(date,this._start);
return this._pixelsPerInterval*numeric/this._interval;
};

Timeline.LinearEther.prototype.pixelOffsetToDate=function(pixels){
var numeric=pixels*this._interval/this._pixelsPerInterval;
return this._unit.change(this._start,numeric);
};



Timeline.HotZoneEther=function(params){
this._params=params;
this._interval=params.interval;
this._pixelsPerInterval=params.pixelsPerInterval;
};

Timeline.HotZoneEther.prototype.initialize=function(timeline){
this._timeline=timeline;
this._unit=timeline.getUnit();

this._zones=[{
startTime:Number.NEGATIVE_INFINITY,
endTime:Number.POSITIVE_INFINITY,
magnify:1
}];
var params=this._params;
for(var i=0;i<params.zones.length;i++){
var zone=params.zones[i];
var zoneStart=this._unit.parseFromObject(zone.start);
var zoneEnd=this._unit.parseFromObject(zone.end);

for(var j=0;j<this._zones.length&&this._unit.compare(zoneEnd,zoneStart)>0;j++){
var zone2=this._zones[j];

if(this._unit.compare(zoneStart,zone2.endTime)<0){
if(this._unit.compare(zoneStart,zone2.startTime)>0){
this._zones.splice(j,0,{
startTime:zone2.startTime,
endTime:zoneStart,
magnify:zone2.magnify
});
j++;

zone2.startTime=zoneStart;
}

if(this._unit.compare(zoneEnd,zone2.endTime)<0){
this._zones.splice(j,0,{
startTime:zoneStart,
endTime:zoneEnd,
magnify:zone.magnify*zone2.magnify
});
j++;

zone2.startTime=zoneEnd;
zoneStart=zoneEnd;
}else{
zone2.magnify*=zone.magnify;
zoneStart=zone2.endTime;
}
}
}
}

if("startsOn"in this._params){
this._start=this._unit.parseFromObject(this._params.startsOn);
}else if("endsOn"in this._params){
this._start=this._unit.parseFromObject(this._params.endsOn);
this.shiftPixels(-this._timeline.getPixelLength());
}else if("centersOn"in this._params){
this._start=this._unit.parseFromObject(this._params.centersOn);
this.shiftPixels(-this._timeline.getPixelLength()/2);
}else{
this._start=this._unit.makeDefaultValue();
this.shiftPixels(-this._timeline.getPixelLength()/2);
}
};

Timeline.HotZoneEther.prototype.setDate=function(date){
this._start=this._unit.cloneValue(date);
};

Timeline.HotZoneEther.prototype.shiftPixels=function(pixels){
this._start=this.pixelOffsetToDate(pixels);
};

Timeline.HotZoneEther.prototype.dateToPixelOffset=function(date){
return this._dateDiffToPixelOffset(this._start,date);
};

Timeline.HotZoneEther.prototype.pixelOffsetToDate=function(pixels){
return this._pixelOffsetToDate(pixels,this._start);
};

Timeline.HotZoneEther.prototype._dateDiffToPixelOffset=function(fromDate,toDate){
var scale=this._getScale();
var fromTime=fromDate;
var toTime=toDate;

var pixels=0;
if(this._unit.compare(fromTime,toTime)<0){
var z=0;
while(z<this._zones.length){
if(this._unit.compare(fromTime,this._zones[z].endTime)<0){
break;
}
z++;
}

while(this._unit.compare(fromTime,toTime)<0){
var zone=this._zones[z];
var toTime2=this._unit.earlier(toTime,zone.endTime);

pixels+=(this._unit.compare(toTime2,fromTime)/(scale/zone.magnify));

fromTime=toTime2;
z++;
}
}else{
var z=this._zones.length-1;
while(z>=0){
if(this._unit.compare(fromTime,this._zones[z].startTime)>0){
break;
}
z--;
}

while(this._unit.compare(fromTime,toTime)>0){
var zone=this._zones[z];
var toTime2=this._unit.later(toTime,zone.startTime);

pixels+=(this._unit.compare(toTime2,fromTime)/(scale/zone.magnify));

fromTime=toTime2;
z--;
}
}
return pixels;
};

Timeline.HotZoneEther.prototype._pixelOffsetToDate=function(pixels,fromDate){
var scale=this._getScale();
var time=fromDate;
if(pixels>0){
var z=0;
while(z<this._zones.length){
if(this._unit.compare(time,this._zones[z].endTime)<0){
break;
}
z++;
}

while(pixels>0){
var zone=this._zones[z];
var scale2=scale/zone.magnify;

if(zone.endTime==Number.POSITIVE_INFINITY){
time=this._unit.change(time,pixels*scale2);
pixels=0;
}else{
var pixels2=this._unit.compare(zone.endTime,time)/scale2;
if(pixels2>pixels){
time=this._unit.change(time,pixels*scale2);
pixels=0;
}else{
time=zone.endTime;
pixels-=pixels2;
}
}
z++;
}
}else{
var z=this._zones.length-1;
while(z>=0){
if(this._unit.compare(time,this._zones[z].startTime)>0){
break;
}
z--;
}

pixels=-pixels;
while(pixels>0){
var zone=this._zones[z];
var scale2=scale/zone.magnify;

if(zone.startTime==Number.NEGATIVE_INFINITY){
time=this._unit.change(time,-pixels*scale2);
pixels=0;
}else{
var pixels2=this._unit.compare(time,zone.startTime)/scale2;
if(pixels2>pixels){
time=this._unit.change(time,-pixels*scale2);
pixels=0;
}else{
time=zone.startTime;
pixels-=pixels2;
}
}
z--;
}
}
return time;
};

Timeline.HotZoneEther.prototype._getScale=function(){
return this._interval/this._pixelsPerInterval;
};


/* labellers.js */



Timeline.GregorianDateLabeller=function(locale,timeZone){
this._locale=locale;
this._timeZone=timeZone;
};

Timeline.GregorianDateLabeller.monthNames=[];
Timeline.GregorianDateLabeller.dayNames=[];
Timeline.GregorianDateLabeller.labelIntervalFunctions=[];

Timeline.GregorianDateLabeller.getMonthName=function(month,locale){
return Timeline.GregorianDateLabeller.monthNames[locale][month];
};

Timeline.GregorianDateLabeller.prototype.labelInterval=function(date,intervalUnit){
var f=Timeline.GregorianDateLabeller.labelIntervalFunctions[this._locale];
if(f==null){
f=Timeline.GregorianDateLabeller.prototype.defaultLabelInterval;
}
return f.call(this,date,intervalUnit);
};

Timeline.GregorianDateLabeller.prototype.labelPrecise=function(date){
return SimileAjax.DateTime.removeTimeZoneOffset(
date,
this._timeZone
).toUTCString();
};

Timeline.GregorianDateLabeller.prototype.defaultLabelInterval=function(date,intervalUnit){
var text;
var emphasized=false;

date=SimileAjax.DateTime.removeTimeZoneOffset(date,this._timeZone);

switch(intervalUnit){
case SimileAjax.DateTime.MILLISECOND:
text=date.getUTCMilliseconds();
break;
case SimileAjax.DateTime.SECOND:
text=date.getUTCSeconds();
break;
case SimileAjax.DateTime.MINUTE:
var m=date.getUTCMinutes();
if(m==0){
text=date.getUTCHours()+":00";
emphasized=true;
}else{
text=m;
}
break;
case SimileAjax.DateTime.HOUR:
text=date.getUTCHours()+"hr";
break;
case SimileAjax.DateTime.DAY:
text=Timeline.GregorianDateLabeller.getMonthName(date.getUTCMonth(),this._locale)+" "+date.getUTCDate();
break;
case SimileAjax.DateTime.WEEK:
text=Timeline.GregorianDateLabeller.getMonthName(date.getUTCMonth(),this._locale)+" "+date.getUTCDate();
break;
case SimileAjax.DateTime.MONTH:
var m=date.getUTCMonth();
if(m!=0){
text=Timeline.GregorianDateLabeller.getMonthName(m,this._locale);
break;
}
case SimileAjax.DateTime.YEAR:
case SimileAjax.DateTime.DECADE:
case SimileAjax.DateTime.CENTURY:
case SimileAjax.DateTime.MILLENNIUM:
var y=date.getUTCFullYear();
if(y>0){
text=date.getUTCFullYear();
}else{
text=(1-y)+"BC";
}
emphasized=
(intervalUnit==SimileAjax.DateTime.MONTH)||
(intervalUnit==SimileAjax.DateTime.DECADE&&y%100==0)||
(intervalUnit==SimileAjax.DateTime.CENTURY&&y%1000==0);
break;
default:
text=date.toUTCString();
}
return{text:text,emphasized:emphasized};
}



/* original-painter.js */



Timeline.OriginalEventPainter=function(params){
this._params=params;
this._onSelectListeners=[];

this._filterMatcher=null;
this._highlightMatcher=null;
this._frc=null;

this._eventIdToElmt={};
};

Timeline.OriginalEventPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._backLayer=null;
this._eventLayer=null;
this._lineLayer=null;
this._highlightLayer=null;

this._eventIdToElmt=null;
};

Timeline.OriginalEventPainter.prototype.addOnSelectListener=function(listener){
this._onSelectListeners.push(listener);
};

Timeline.OriginalEventPainter.prototype.removeOnSelectListener=function(listener){
for(var i=0;i<this._onSelectListeners.length;i++){
if(this._onSelectListeners[i]==listener){
this._onSelectListeners.splice(i,1);
break;
}
}
};

Timeline.OriginalEventPainter.prototype.getFilterMatcher=function(){
return this._filterMatcher;
};

Timeline.OriginalEventPainter.prototype.setFilterMatcher=function(filterMatcher){
this._filterMatcher=filterMatcher;
};

Timeline.OriginalEventPainter.prototype.getHighlightMatcher=function(){
return this._highlightMatcher;
};

Timeline.OriginalEventPainter.prototype.setHighlightMatcher=function(highlightMatcher){
this._highlightMatcher=highlightMatcher;
};

Timeline.OriginalEventPainter.prototype.paint=function(){
var eventSource=this._band.getEventSource();
if(eventSource==null){
return;
}

this._eventIdToElmt={};
this._prepareForPainting();

var eventTheme=this._params.theme.event;
var trackHeight=Math.max(eventTheme.track.height,eventTheme.tape.height+this._frc.getLineHeight());
var metrics={
trackOffset:eventTheme.track.gap,
trackHeight:trackHeight,
trackGap:eventTheme.track.gap,
trackIncrement:trackHeight+eventTheme.track.gap,
icon:eventTheme.instant.icon,
iconWidth:eventTheme.instant.iconWidth,
iconHeight:eventTheme.instant.iconHeight,
labelWidth:eventTheme.label.width
}

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

var filterMatcher=(this._filterMatcher!=null)?
this._filterMatcher:
function(evt){return true;};
var highlightMatcher=(this._highlightMatcher!=null)?
this._highlightMatcher:
function(evt){return-1;};

var iterator=eventSource.getEventReverseIterator(minDate,maxDate);
while(iterator.hasNext()){
var evt=iterator.next();
if(filterMatcher(evt)){
this.paintEvent(evt,metrics,this._params.theme,highlightMatcher(evt));
}
}

this._highlightLayer.style.display="block";
this._lineLayer.style.display="block";
this._eventLayer.style.display="block";
};

Timeline.OriginalEventPainter.prototype.softPaint=function(){
};

Timeline.OriginalEventPainter.prototype._prepareForPainting=function(){
var band=this._band;

if(this._backLayer==null){
this._backLayer=this._band.createLayerDiv(0,"timeline-band-events");
this._backLayer.style.visibility="hidden";

var eventLabelPrototype=document.createElement("span");
eventLabelPrototype.className="timeline-event-label";
this._backLayer.appendChild(eventLabelPrototype);
this._frc=SimileAjax.Graphics.getFontRenderingContext(eventLabelPrototype);
}
this._frc.update();
this._tracks=[];

if(this._highlightLayer!=null){
band.removeLayerDiv(this._highlightLayer);
}
this._highlightLayer=band.createLayerDiv(105,"timeline-band-highlights");
this._highlightLayer.style.display="none";

if(this._lineLayer!=null){
band.removeLayerDiv(this._lineLayer);
}
this._lineLayer=band.createLayerDiv(110,"timeline-band-lines");
this._lineLayer.style.display="none";

if(this._eventLayer!=null){
band.removeLayerDiv(this._eventLayer);
}
this._eventLayer=band.createLayerDiv(115,"timeline-band-events");
this._eventLayer.style.display="none";
};

Timeline.OriginalEventPainter.prototype.paintEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isInstant()){
this.paintInstantEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintDurationEvent(evt,metrics,theme,highlightIndex);
}
};

Timeline.OriginalEventPainter.prototype.paintInstantEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isImprecise()){
this.paintImpreciseInstantEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintPreciseInstantEvent(evt,metrics,theme,highlightIndex);
}
}

Timeline.OriginalEventPainter.prototype.paintDurationEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isImprecise()){
this.paintImpreciseDurationEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintPreciseDurationEvent(evt,metrics,theme,highlightIndex);
}
}

Timeline.OriginalEventPainter.prototype.paintPreciseInstantEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var iconRightEdge=Math.round(startPixel+metrics.iconWidth/2);
var iconLeftEdge=Math.round(startPixel-metrics.iconWidth/2);

var labelSize=this._frc.computeSize(text);
var labelLeft=iconRightEdge+theme.event.label.offsetFromLine;
var labelRight=labelLeft+labelSize.width;

var rightEdge=labelRight;
var track=this._findFreeTrack(rightEdge);

var labelTop=Math.round(
metrics.trackOffset+track*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var iconElmtData=this._paintEventIcon(evt,track,iconLeftEdge,metrics,theme);
var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(iconElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(iconElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,iconElmtData,theme);

this._eventIdToElmt[evt.getID()]=iconElmtData.elmt;
this._tracks[track]=iconLeftEdge;
};

Timeline.OriginalEventPainter.prototype.paintImpreciseInstantEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var endDate=evt.getEnd();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));

var iconRightEdge=Math.round(startPixel+metrics.iconWidth/2);
var iconLeftEdge=Math.round(startPixel-metrics.iconWidth/2);

var labelSize=this._frc.computeSize(text);
var labelLeft=iconRightEdge+theme.event.label.offsetFromLine;
var labelRight=labelLeft+labelSize.width;

var rightEdge=Math.max(labelRight,endPixel);
var track=this._findFreeTrack(rightEdge);
var labelTop=Math.round(
metrics.trackOffset+track*metrics.trackIncrement+
metrics.trackHeight/2-labelSize.height/2);

var iconElmtData=this._paintEventIcon(evt,track,iconLeftEdge,metrics,theme);
var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);
var tapeElmtData=this._paintEventTape(evt,track,startPixel,endPixel,
theme.event.instant.impreciseColor,theme.event.instant.impreciseOpacity,metrics,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(iconElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(iconElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,iconElmtData,theme);

this._eventIdToElmt[evt.getID()]=iconElmtData.elmt;
this._tracks[track]=iconLeftEdge;
};

Timeline.OriginalEventPainter.prototype.paintPreciseDurationEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var endDate=evt.getEnd();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));

var labelSize=this._frc.computeSize(text);
var labelLeft=startPixel;
var labelRight=labelLeft+labelSize.width;

var rightEdge=Math.max(labelRight,endPixel);
var track=this._findFreeTrack(rightEdge);
var labelTop=Math.round(
metrics.trackOffset+track*metrics.trackIncrement+theme.event.tape.height);

var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var tapeElmtData=this._paintEventTape(evt,track,startPixel,endPixel,color,100,metrics,theme);
var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(tapeElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,tapeElmtData,theme);

this._eventIdToElmt[evt.getID()]=tapeElmtData.elmt;
this._tracks[track]=startPixel;
};

Timeline.OriginalEventPainter.prototype.paintImpreciseDurationEvent=function(evt,metrics,theme,highlightIndex){
var doc=this._timeline.getDocument();
var text=evt.getText();

var startDate=evt.getStart();
var latestStartDate=evt.getLatestStart();
var endDate=evt.getEnd();
var earliestEndDate=evt.getEarliestEnd();

var startPixel=Math.round(this._band.dateToPixelOffset(startDate));
var latestStartPixel=Math.round(this._band.dateToPixelOffset(latestStartDate));
var endPixel=Math.round(this._band.dateToPixelOffset(endDate));
var earliestEndPixel=Math.round(this._band.dateToPixelOffset(earliestEndDate));

var labelSize=this._frc.computeSize(text);
var labelLeft=latestStartPixel;
var labelRight=labelLeft+labelSize.width;

var rightEdge=Math.max(labelRight,endPixel);
var track=this._findFreeTrack(rightEdge);
var labelTop=Math.round(
metrics.trackOffset+track*metrics.trackIncrement+theme.event.tape.height);

var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var impreciseTapeElmtData=this._paintEventTape(evt,track,startPixel,endPixel,
theme.event.duration.impreciseColor,theme.event.duration.impreciseOpacity,metrics,theme);
var tapeElmtData=this._paintEventTape(evt,track,latestStartPixel,earliestEndPixel,color,100,metrics,theme);

var labelElmtData=this._paintEventLabel(evt,text,labelLeft,labelTop,labelSize.width,labelSize.height,theme);

var self=this;
var clickHandler=function(elmt,domEvt,target){
return self._onClickInstantEvent(tapeElmtData.elmt,domEvt,evt);
};
SimileAjax.DOM.registerEvent(tapeElmtData.elmt,"mousedown",clickHandler);
SimileAjax.DOM.registerEvent(labelElmtData.elmt,"mousedown",clickHandler);

this._createHighlightDiv(highlightIndex,tapeElmtData,theme);

this._eventIdToElmt[evt.getID()]=tapeElmtData.elmt;
this._tracks[track]=startPixel;
};

Timeline.OriginalEventPainter.prototype._findFreeTrack=function(rightEdge){
for(var i=0;i<this._tracks.length;i++){
var t=this._tracks[i];
if(t>rightEdge){
break;
}
}
return i;
};

Timeline.OriginalEventPainter.prototype._paintEventIcon=function(evt,iconTrack,left,metrics,theme){
var icon=evt.getIcon();
icon=icon!=null?icon:metrics.icon;

var middle=metrics.trackOffset+iconTrack*metrics.trackIncrement+metrics.trackHeight/2;
var top=Math.round(middle-metrics.iconHeight/2);

var img=SimileAjax.Graphics.createTranslucentImage(icon);
var iconDiv=this._timeline.getDocument().createElement("div");
iconDiv.style.position="absolute";
iconDiv.style.left=left+"px";
iconDiv.style.top=top+"px";
iconDiv.appendChild(img);
iconDiv.style.cursor="pointer";
this._eventLayer.appendChild(iconDiv);

return{
left:left,
top:top,
width:metrics.iconWidth,
height:metrics.iconHeight,
elmt:iconDiv
};
};

Timeline.OriginalEventPainter.prototype._paintEventLabel=function(evt,text,left,top,width,height,theme){
var doc=this._timeline.getDocument();

var labelDiv=doc.createElement("div");
labelDiv.style.position="absolute";
labelDiv.style.left=left+"px";
labelDiv.style.width=width+"px";
labelDiv.style.top=top+"px";
labelDiv.innerHTML=text;
labelDiv.style.cursor="pointer";

var color=evt.getTextColor();
if(color==null){
color=evt.getColor();
}
if(color!=null){
labelDiv.style.color=color;
}

this._eventLayer.appendChild(labelDiv);

return{
left:left,
top:top,
width:width,
height:height,
elmt:labelDiv
};
};

Timeline.OriginalEventPainter.prototype._paintEventTape=function(
evt,iconTrack,startPixel,endPixel,color,opacity,metrics,theme){

var tapeWidth=endPixel-startPixel;
var tapeHeight=theme.event.tape.height;
var top=metrics.trackOffset+iconTrack*metrics.trackIncrement;

var tapeDiv=this._timeline.getDocument().createElement("div");
tapeDiv.style.position="absolute";
tapeDiv.style.left=startPixel+"px";
tapeDiv.style.width=tapeWidth+"px";
tapeDiv.style.top=top+"px";
tapeDiv.style.height=tapeHeight+"px";
tapeDiv.style.backgroundColor=color;
tapeDiv.style.overflow="hidden";
tapeDiv.style.cursor="pointer";
SimileAjax.Graphics.setOpacity(tapeDiv,opacity);

this._eventLayer.appendChild(tapeDiv);

return{
left:startPixel,
top:top,
width:tapeWidth,
height:tapeHeight,
elmt:tapeDiv
};
}

Timeline.OriginalEventPainter.prototype._createHighlightDiv=function(highlightIndex,dimensions,theme){
if(highlightIndex>=0){
var doc=this._timeline.getDocument();
var eventTheme=theme.event;

var color=eventTheme.highlightColors[Math.min(highlightIndex,eventTheme.highlightColors.length-1)];

var div=doc.createElement("div");
div.style.position="absolute";
div.style.overflow="hidden";
div.style.left=(dimensions.left-2)+"px";
div.style.width=(dimensions.width+4)+"px";
div.style.top=(dimensions.top-2)+"px";
div.style.height=(dimensions.height+4)+"px";
div.style.background=color;

this._highlightLayer.appendChild(div);
}
};

Timeline.OriginalEventPainter.prototype._onClickInstantEvent=function(icon,domEvt,evt){
var c=SimileAjax.DOM.getPageCoordinates(icon);
this._showBubble(
c.left+Math.ceil(icon.offsetWidth/2),
c.top+Math.ceil(icon.offsetHeight/2),
evt
);
this._fireOnSelect(evt.getID());

domEvt.cancelBubble=true;
SimileAjax.DOM.cancelEvent(domEvt);
return false;
};

Timeline.OriginalEventPainter.prototype._onClickDurationEvent=function(target,domEvt,evt){
if("pageX"in domEvt){
var x=domEvt.pageX;
var y=domEvt.pageY;
}else{
var c=SimileAjax.DOM.getPageCoordinates(target);
var x=domEvt.offsetX+c.left;
var y=domEvt.offsetY+c.top;
}
this._showBubble(x,y,evt);
this._fireOnSelect(evt.getID());

domEvt.cancelBubble=true;
SimileAjax.DOM.cancelEvent(domEvt);
return false;
};

Timeline.OriginalEventPainter.prototype.showBubble=function(evt){
var elmt=this._eventIdToElmt[evt.getID()];
if(elmt){
var c=SimileAjax.DOM.getPageCoordinates(elmt);
this._showBubble(c.left+elmt.offsetWidth/2,c.top+elmt.offsetHeight/2,evt);
}
};

Timeline.OriginalEventPainter.prototype._showBubble=function(x,y,evt){
var div=document.createElement("div");
evt.fillInfoBubble(div,this._params.theme,this._band.getLabeller());

SimileAjax.WindowManager.cancelPopups();
SimileAjax.Graphics.createBubbleForContentAndPoint(div,x,y,this._params.theme.event.bubble.width);
};

Timeline.OriginalEventPainter.prototype._fireOnSelect=function(eventID){
for(var i=0;i<this._onSelectListeners.length;i++){
this._onSelectListeners[i](eventID);
}
};


/* overview-painter.js */



Timeline.OverviewEventPainter=function(params){
this._params=params;
this._onSelectListeners=[];

this._filterMatcher=null;
this._highlightMatcher=null;
};

Timeline.OverviewEventPainter.prototype.initialize=function(band,timeline){
this._band=band;
this._timeline=timeline;

this._eventLayer=null;
this._highlightLayer=null;
};

Timeline.OverviewEventPainter.prototype.addOnSelectListener=function(listener){
this._onSelectListeners.push(listener);
};

Timeline.OverviewEventPainter.prototype.removeOnSelectListener=function(listener){
for(var i=0;i<this._onSelectListeners.length;i++){
if(this._onSelectListeners[i]==listener){
this._onSelectListeners.splice(i,1);
break;
}
}
};

Timeline.OverviewEventPainter.prototype.getFilterMatcher=function(){
return this._filterMatcher;
};

Timeline.OverviewEventPainter.prototype.setFilterMatcher=function(filterMatcher){
this._filterMatcher=filterMatcher;
};

Timeline.OverviewEventPainter.prototype.getHighlightMatcher=function(){
return this._highlightMatcher;
};

Timeline.OverviewEventPainter.prototype.setHighlightMatcher=function(highlightMatcher){
this._highlightMatcher=highlightMatcher;
};

Timeline.OverviewEventPainter.prototype.paint=function(){
var eventSource=this._band.getEventSource();
if(eventSource==null){
return;
}

this._prepareForPainting();

var eventTheme=this._params.theme.event;
var metrics={
trackOffset:eventTheme.overviewTrack.offset,
trackHeight:eventTheme.overviewTrack.height,
trackGap:eventTheme.overviewTrack.gap,
trackIncrement:eventTheme.overviewTrack.height+eventTheme.overviewTrack.gap
}

var minDate=this._band.getMinDate();
var maxDate=this._band.getMaxDate();

var filterMatcher=(this._filterMatcher!=null)?
this._filterMatcher:
function(evt){return true;};
var highlightMatcher=(this._highlightMatcher!=null)?
this._highlightMatcher:
function(evt){return-1;};

var iterator=eventSource.getEventReverseIterator(minDate,maxDate);
while(iterator.hasNext()){
var evt=iterator.next();
if(filterMatcher(evt)){
this.paintEvent(evt,metrics,this._params.theme,highlightMatcher(evt));
}
}

this._highlightLayer.style.display="block";
this._eventLayer.style.display="block";
};

Timeline.OverviewEventPainter.prototype.softPaint=function(){
};

Timeline.OverviewEventPainter.prototype._prepareForPainting=function(){
var band=this._band;

this._tracks=[];

if(this._highlightLayer!=null){
band.removeLayerDiv(this._highlightLayer);
}
this._highlightLayer=band.createLayerDiv(105,"timeline-band-highlights");
this._highlightLayer.style.display="none";

if(this._eventLayer!=null){
band.removeLayerDiv(this._eventLayer);
}
this._eventLayer=band.createLayerDiv(110,"timeline-band-events");
this._eventLayer.style.display="none";
};

Timeline.OverviewEventPainter.prototype.paintEvent=function(evt,metrics,theme,highlightIndex){
if(evt.isInstant()){
this.paintInstantEvent(evt,metrics,theme,highlightIndex);
}else{
this.paintDurationEvent(evt,metrics,theme,highlightIndex);
}
};

Timeline.OverviewEventPainter.prototype.paintInstantEvent=function(evt,metrics,theme,highlightIndex){
var startDate=evt.getStart();
var startPixel=Math.round(this._band.dateToPixelOffset(startDate));

var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var tickElmtData=this._paintEventTick(evt,startPixel,color,100,metrics,theme);

this._createHighlightDiv(highlightIndex,tickElmtData,theme);
};

Timeline.OverviewEventPainter.prototype.paintDurationEvent=function(evt,metrics,theme,highlightIndex){
var latestStartDate=evt.getLatestStart();
var earliestEndDate=evt.getEarliestEnd();

var latestStartPixel=Math.round(this._band.dateToPixelOffset(latestStartDate));
var earliestEndPixel=Math.round(this._band.dateToPixelOffset(earliestEndDate));

var tapeTrack=0;
for(;tapeTrack<this._tracks.length;tapeTrack++){
if(earliestEndPixel<this._tracks[tapeTrack]){
break;
}
}
this._tracks[tapeTrack]=earliestEndPixel;

var color=evt.getColor();
color=color!=null?color:theme.event.duration.color;

var tapeElmtData=this._paintEventTape(evt,tapeTrack,latestStartPixel,earliestEndPixel,color,100,metrics,theme);

this._createHighlightDiv(highlightIndex,tapeElmtData,theme);
};

Timeline.OverviewEventPainter.prototype._paintEventTape=function(
evt,track,left,right,color,opacity,metrics,theme){

var top=metrics.trackOffset+track*metrics.trackIncrement;
var width=right-left;
var height=metrics.trackHeight;

var tapeDiv=this._timeline.getDocument().createElement("div");
tapeDiv.style.position="absolute";
tapeDiv.style.left=left+"px";
tapeDiv.style.width=width+"px";
tapeDiv.style.top=top+"px";
tapeDiv.style.height=height+"px";
tapeDiv.style.backgroundColor=color;
tapeDiv.style.overflow="hidden";
SimileAjax.Graphics.setOpacity(tapeDiv,opacity);

this._eventLayer.appendChild(tapeDiv);

return{
left:left,
top:top,
width:width,
height:height,
elmt:tapeDiv
};
}

Timeline.OverviewEventPainter.prototype._paintEventTick=function(
evt,left,color,opacity,metrics,theme){

var height=theme.event.overviewTrack.tickHeight;
var top=metrics.trackOffset-height;
var width=1;

var tickDiv=this._timeline.getDocument().createElement("div");
tickDiv.style.position="absolute";
tickDiv.style.left=left+"px";
tickDiv.style.width=width+"px";
tickDiv.style.top=top+"px";
tickDiv.style.height=height+"px";
tickDiv.style.backgroundColor=color;
tickDiv.style.overflow="hidden";
SimileAjax.Graphics.setOpacity(tickDiv,opacity);

this._eventLayer.appendChild(tickDiv);

return{
left:left,
top:top,
width:width,
height:height,
elmt:tickDiv
};
}

Timeline.OverviewEventPainter.prototype._createHighlightDiv=function(highlightIndex,dimensions,theme){
if(highlightIndex>=0){
var doc=this._timeline.getDocument();
var eventTheme=theme.event;

var color=eventTheme.highlightColors[Math.min(highlightIndex,eventTheme.highlightColors.length-1)];

var div=doc.createElement("div");
div.style.position="absolute";
div.style.overflow="hidden";
div.style.left=(dimensions.left-1)+"px";
div.style.width=(dimensions.width+2)+"px";
div.style.top=(dimensions.top-1)+"px";
div.style.height=(dimensions.height+2)+"px";
div.style.background=color;

this._highlightLayer.appendChild(div);
}
};

Timeline.OverviewEventPainter.prototype.showBubble=function(evt){

};


/* sources.js */




Timeline.DefaultEventSource=function(eventIndex){
this._events=(eventIndex instanceof Object)?eventIndex:new SimileAjax.EventIndex();
this._listeners=[];
};

Timeline.DefaultEventSource.prototype.addListener=function(listener){
this._listeners.push(listener);
};

Timeline.DefaultEventSource.prototype.removeListener=function(listener){
for(var i=0;i<this._listeners.length;i++){
if(this._listeners[i]==listener){
this._listeners.splice(i,1);
break;
}
}
};

Timeline.DefaultEventSource.prototype.loadXML=function(xml,url){
var base=this._getBaseURL(url);

var wikiURL=xml.documentElement.getAttribute("wiki-url");
var wikiSection=xml.documentElement.getAttribute("wiki-section");

var dateTimeFormat=xml.documentElement.getAttribute("date-time-format");
var parseDateTimeFunction=this._events.getUnit().getParser(dateTimeFormat);

var node=xml.documentElement.firstChild;
var added=false;
while(node!=null){
if(node.nodeType==1){
var description="";
if(node.firstChild!=null&&node.firstChild.nodeType==3){
description=node.firstChild.nodeValue;
}
var evt=new Timeline.DefaultEventSource.Event(
node.getAttribute("id"),
parseDateTimeFunction(node.getAttribute("start")),
parseDateTimeFunction(node.getAttribute("end")),
parseDateTimeFunction(node.getAttribute("latestStart")),
parseDateTimeFunction(node.getAttribute("earliestEnd")),
node.getAttribute("isDuration")!="true",
node.getAttribute("title"),
description,
this._resolveRelativeURL(node.getAttribute("image"),base),
this._resolveRelativeURL(node.getAttribute("link"),base),
this._resolveRelativeURL(node.getAttribute("icon"),base),
node.getAttribute("color"),
node.getAttribute("textColor")
);
evt._node=node;
evt.getProperty=function(name){
return this._node.getAttribute(name);
};
evt.setWikiInfo(wikiURL,wikiSection);

this._events.add(evt);

added=true;
}
node=node.nextSibling;
}

if(added){
this._fire("onAddMany",[]);
}
};


Timeline.DefaultEventSource.prototype.loadJSON=function(data,url){
var base=this._getBaseURL(url);
var added=false;
if(data&&data.events){
var wikiURL=("wikiURL"in data)?data.wikiURL:null;
var wikiSection=("wikiSection"in data)?data.wikiSection:null;

var dateTimeFormat=("dateTimeFormat"in data)?data.dateTimeFormat:null;
var parseDateTimeFunction=this._events.getUnit().getParser(dateTimeFormat);

for(var i=0;i<data.events.length;i++){
var event=data.events[i];
var evt=new Timeline.DefaultEventSource.Event(
("id"in event)?event.id:undefined,
parseDateTimeFunction(event.start),
parseDateTimeFunction(event.end),
parseDateTimeFunction(event.latestStart),
parseDateTimeFunction(event.earliestEnd),
event.isDuration||false,
event.title,
event.description,
this._resolveRelativeURL(event.image,base),
this._resolveRelativeURL(event.link,base),
this._resolveRelativeURL(event.icon,base),
event.color,
event.textColor
);
evt._obj=event;
evt.getProperty=function(name){
return this._obj[name];
};
evt.setWikiInfo(wikiURL,wikiSection);

this._events.add(evt);
added=true;
}
}

if(added){
this._fire("onAddMany",[]);
}
};


Timeline.DefaultEventSource.prototype.loadSPARQL=function(xml,url){
var base=this._getBaseURL(url);

var dateTimeFormat='iso8601';
var parseDateTimeFunction=this._events.getUnit().getParser(dateTimeFormat);

if(xml==null){
return;
}


var node=xml.documentElement.firstChild;
while(node!=null&&(node.nodeType!=1||node.nodeName!='results')){
node=node.nextSibling;
}

var wikiURL=null;
var wikiSection=null;
if(node!=null){
wikiURL=node.getAttribute("wiki-url");
wikiSection=node.getAttribute("wiki-section");

node=node.firstChild;
}

var added=false;
while(node!=null){
if(node.nodeType==1){
var bindings={};
var binding=node.firstChild;
while(binding!=null){
if(binding.nodeType==1&&
binding.firstChild!=null&&
binding.firstChild.nodeType==1&&
binding.firstChild.firstChild!=null&&
binding.firstChild.firstChild.nodeType==3){
bindings[binding.getAttribute('name')]=binding.firstChild.firstChild.nodeValue;
}
binding=binding.nextSibling;
}

if(bindings["start"]==null&&bindings["date"]!=null){
bindings["start"]=bindings["date"];
}

var evt=new Timeline.DefaultEventSource.Event(
bindings["id"],
parseDateTimeFunction(bindings["start"]),
parseDateTimeFunction(bindings["end"]),
parseDateTimeFunction(bindings["latestStart"]),
parseDateTimeFunction(bindings["earliestEnd"]),
bindings["isDuration"]!="true",
bindings["title"],
bindings["description"],
this._resolveRelativeURL(bindings["image"],base),
this._resolveRelativeURL(bindings["link"],base),
this._resolveRelativeURL(bindings["icon"],base),
bindings["color"],
bindings["textColor"]
);
evt._bindings=bindings;
evt.getProperty=function(name){
return this._bindings[name];
};
evt.setWikiInfo(wikiURL,wikiSection);

this._events.add(evt);
added=true;
}
node=node.nextSibling;
}

if(added){
this._fire("onAddMany",[]);
}
};

Timeline.DefaultEventSource.prototype.add=function(evt){
this._events.add(evt);
this._fire("onAddOne",[evt]);
};

Timeline.DefaultEventSource.prototype.addMany=function(events){
for(var i=0;i<events.length;i++){
this._events.add(events[i]);
}
this._fire("onAddMany",[]);
};

Timeline.DefaultEventSource.prototype.clear=function(){
this._events.removeAll();
this._fire("onClear",[]);
};

Timeline.DefaultEventSource.prototype.getEvent=function(id){
return this._events.getEvent(id);
};

Timeline.DefaultEventSource.prototype.getEventIterator=function(startDate,endDate){
return this._events.getIterator(startDate,endDate);
};

Timeline.DefaultEventSource.prototype.getEventReverseIterator=function(startDate,endDate){
return this._events.getReverseIterator(startDate,endDate);
};

Timeline.DefaultEventSource.prototype.getAllEventIterator=function(){
return this._events.getAllIterator();
};

Timeline.DefaultEventSource.prototype.getCount=function(){
return this._events.getCount();
};

Timeline.DefaultEventSource.prototype.getEarliestDate=function(){
return this._events.getEarliestDate();
};

Timeline.DefaultEventSource.prototype.getLatestDate=function(){
return this._events.getLatestDate();
};

Timeline.DefaultEventSource.prototype._fire=function(handlerName,args){
for(var i=0;i<this._listeners.length;i++){
var listener=this._listeners[i];
if(handlerName in listener){
try{
listener[handlerName].apply(listener,args);
}catch(e){
SimileAjax.Debug.exception(e);
}
}
}
};

Timeline.DefaultEventSource.prototype._getBaseURL=function(url){
if(url.indexOf("://")<0){
var url2=this._getBaseURL(document.location.href);
if(url.substr(0,1)=="/"){
url=url2.substr(0,url2.indexOf("/",url2.indexOf("://")+3))+url;
}else{
url=url2+url;
}
}

var i=url.lastIndexOf("/");
if(i<0){
return"";
}else{
return url.substr(0,i+1);
}
};

Timeline.DefaultEventSource.prototype._resolveRelativeURL=function(url,base){
if(url==null||url==""){
return url;
}else if(url.indexOf("://")>0){
return url;
}else if(url.substr(0,1)=="/"){
return base.substr(0,base.indexOf("/",base.indexOf("://")+3))+url;
}else{
return base+url;
}
};


Timeline.DefaultEventSource.Event=function(
id,
start,end,latestStart,earliestEnd,instant,
text,description,image,link,
icon,color,textColor){

id=(id)?id.trim():"";
this._id=id.length>0?id:("e"+Math.floor(Math.random()*1000000));

this._instant=instant||(end==null);

this._start=start;
this._end=(end!=null)?end:start;

this._latestStart=(latestStart!=null)?latestStart:(instant?this._end:this._start);
this._earliestEnd=(earliestEnd!=null)?earliestEnd:(instant?this._start:this._end);

this._text=SimileAjax.HTML.deEntify(text);
this._description=SimileAjax.HTML.deEntify(description);
this._image=(image!=null&&image!="")?image:null;
this._link=(link!=null&&link!="")?link:null;

this._icon=(icon!=null&&icon!="")?icon:null;
this._color=(color!=null&&color!="")?color:null;
this._textColor=(textColor!=null&&textColor!="")?textColor:null;

this._wikiURL=null;
this._wikiSection=null;
};

Timeline.DefaultEventSource.Event.prototype={
getID:function(){return this._id;},

isInstant:function(){return this._instant;},
isImprecise:function(){return this._start!=this._latestStart||this._end!=this._earliestEnd;},

getStart:function(){return this._start;},
getEnd:function(){return this._end;},
getLatestStart:function(){return this._latestStart;},
getEarliestEnd:function(){return this._earliestEnd;},

getText:function(){return this._text;},
getDescription:function(){return this._description;},
getImage:function(){return this._image;},
getLink:function(){return this._link;},

getIcon:function(){return this._icon;},
getColor:function(){return this._color;},
getTextColor:function(){return this._textColor;},

getProperty:function(name){return null;},

getWikiURL:function(){return this._wikiURL;},
getWikiSection:function(){return this._wikiSection;},
setWikiInfo:function(wikiURL,wikiSection){
this._wikiURL=wikiURL;
this._wikiSection=wikiSection;
},

fillDescription:function(elmt){
elmt.innerHTML=this._description;
},
fillWikiInfo:function(elmt){
if(this._wikiURL!=null&&this._wikiSection!=null){
var wikiID=this.getProperty("wikiID");
if(wikiID==null||wikiID.length==0){
wikiID=this.getText();
}
wikiID=wikiID.replace(/\s/g,"_");

var url=this._wikiURL+this._wikiSection.replace(/\s/g,"_")+"/"+wikiID;
var a=document.createElement("a");
a.href=url;
a.target="new";
a.innerHTML=Timeline.strings[Timeline.clientLocale].wikiLinkLabel;

elmt.appendChild(document.createTextNode("["));
elmt.appendChild(a);
elmt.appendChild(document.createTextNode("]"));
}else{
elmt.style.display="none";
}
},
fillTime:function(elmt,labeller){
if(this._instant){
if(this.isImprecise()){
elmt.appendChild(elmt.ownerDocument.createTextNode(labeller.labelPrecise(this._start)));
elmt.appendChild(elmt.ownerDocument.createElement("br"));
elmt.appendChild(elmt.ownerDocument.createTextNode(labeller.labelPrecise(this._end)));
}else{
elmt.appendChild(elmt.ownerDocument.createTextNode(labeller.labelPrecise(this._start)));
}
}else{
if(this.isImprecise()){
elmt.appendChild(elmt.ownerDocument.createTextNode(
labeller.labelPrecise(this._start)+" ~ "+labeller.labelPrecise(this._latestStart)));
elmt.appendChild(elmt.ownerDocument.createElement("br"));
elmt.appendChild(elmt.ownerDocument.createTextNode(
labeller.labelPrecise(this._earliestEnd)+" ~ "+labeller.labelPrecise(this._end)));
}else{
elmt.appendChild(elmt.ownerDocument.createTextNode(labeller.labelPrecise(this._start)));
elmt.appendChild(elmt.ownerDocument.createElement("br"));
elmt.appendChild(elmt.ownerDocument.createTextNode(labeller.labelPrecise(this._end)));
}
}
},
fillInfoBubble:function(elmt,theme,labeller){
var doc=elmt.ownerDocument;

var title=this.getText();
var link=this.getLink();
var image=this.getImage();

if(image!=null){
var img=doc.createElement("img");
img.src=image;

theme.event.bubble.imageStyler(img);
elmt.appendChild(img);
}

var divTitle=doc.createElement("div");
var textTitle=doc.createTextNode(title);
if(link!=null){
var a=doc.createElement("a");
a.href=link;
a.appendChild(textTitle);
divTitle.appendChild(a);
}else{
divTitle.appendChild(textTitle);
}
theme.event.bubble.titleStyler(divTitle);
elmt.appendChild(divTitle);

var divBody=doc.createElement("div");
this.fillDescription(divBody);
theme.event.bubble.bodyStyler(divBody);
elmt.appendChild(divBody);

var divTime=doc.createElement("div");
this.fillTime(divTime,labeller);
theme.event.bubble.timeStyler(divTime);
elmt.appendChild(divTime);

var divWiki=doc.createElement("div");
this.fillWikiInfo(divWiki);
theme.event.bubble.wikiStyler(divWiki);
elmt.appendChild(divWiki);
}
};

/* themes.js */




Timeline.ClassicTheme=new Object();

Timeline.ClassicTheme.implementations=[];

Timeline.ClassicTheme.create=function(locale){
if(locale==null){
locale=Timeline.getDefaultLocale();
}

var f=Timeline.ClassicTheme.implementations[locale];
if(f==null){
f=Timeline.ClassicTheme._Impl;
}
return new f();
};

Timeline.ClassicTheme._Impl=function(){
this.firstDayOfWeek=0;

this.ether={
backgroundColors:[
"#EEE",
"#DDD",
"#CCC",
"#AAA"
],
highlightColor:"white",
highlightOpacity:50,
interval:{
line:{
show:true,
color:"#aaa",
opacity:25
},
weekend:{
color:"#FFFFE0",
opacity:30
},
marker:{
hAlign:"Bottom",
hBottomStyler:function(elmt){
elmt.className="timeline-ether-marker-bottom";
},
hBottomEmphasizedStyler:function(elmt){
elmt.className="timeline-ether-marker-bottom-emphasized";
},
hTopStyler:function(elmt){
elmt.className="timeline-ether-marker-top";
},
hTopEmphasizedStyler:function(elmt){
elmt.className="timeline-ether-marker-top-emphasized";
},

vAlign:"Right",
vRightStyler:function(elmt){
elmt.className="timeline-ether-marker-right";
},
vRightEmphasizedStyler:function(elmt){
elmt.className="timeline-ether-marker-right-emphasized";
},
vLeftStyler:function(elmt){
elmt.className="timeline-ether-marker-left";
},
vLeftEmphasizedStyler:function(elmt){
elmt.className="timeline-ether-marker-left-emphasized";
}
}
}
};

this.event={
track:{
height:10,
gap:2
},
overviewTrack:{
offset:20,
tickHeight:6,
height:2,
gap:1
},
tape:{
height:4
},
instant:{
icon:Timeline.urlPrefix+"images/dull-blue-circle.png",
iconWidth:10,
iconHeight:10,
color:"#58A0DC",
impreciseColor:"#58A0DC",
impreciseOpacity:20
},
duration:{
color:"#58A0DC",
impreciseColor:"#58A0DC",
impreciseOpacity:20
},
label:{
backgroundColor:"white",
backgroundOpacity:50,
lineColor:"#58A0DC",
offsetFromLine:3
},
highlightColors:[
"#FFFF00",
"#FFC000",
"#FF0000",
"#0000FF"
],
bubble:{
width:250,
height:125,
titleStyler:function(elmt){
elmt.className="timeline-event-bubble-title";
},
bodyStyler:function(elmt){
elmt.className="timeline-event-bubble-body";
},
imageStyler:function(elmt){
elmt.className="timeline-event-bubble-image";
},
wikiStyler:function(elmt){
elmt.className="timeline-event-bubble-wiki";
},
timeStyler:function(elmt){
elmt.className="timeline-event-bubble-time";
}
}
};
};

/* timeline.js */



Timeline.strings={};

Timeline.getDefaultLocale=function(){
return Timeline.clientLocale;
};

Timeline.create=function(elmt,bandInfos,orientation,unit){
return new Timeline._Impl(elmt,bandInfos,orientation,unit);
};

Timeline.HORIZONTAL=0;
Timeline.VERTICAL=1;

Timeline._defaultTheme=null;

Timeline.createBandInfo=function(params){
var theme=("theme"in params)?params.theme:Timeline.getDefaultTheme();

var eventSource=("eventSource"in params)?params.eventSource:null;

var ether=new Timeline.LinearEther({
centersOn:("date"in params)?params.date:new Date(),
interval:SimileAjax.DateTime.gregorianUnitLengths[params.intervalUnit],
pixelsPerInterval:params.intervalPixels
});

var etherPainter=new Timeline.GregorianEtherPainter({
unit:params.intervalUnit,
multiple:("multiple"in params)?params.multiple:1,
theme:theme,
align:("align"in params)?params.align:undefined
});

var eventPainterParams={
showText:("showEventText"in params)?params.showEventText:true,
theme:theme
};
if("trackHeight"in params){
eventPainterParams.trackHeight=params.trackHeight;
}
if("trackGap"in params){
eventPainterParams.trackGap=params.trackGap;
}

var layout=("overview"in params&&params.overview)?"overview":("layout"in params?params.layout:"original");
var eventPainter;
switch(layout){
case"overview":
eventPainter=new Timeline.OverviewEventPainter(eventPainterParams);
break;
case"detailed":
eventPainter=new Timeline.DetailedEventPainter(eventPainterParams);
break;
default:
eventPainter=new Timeline.OriginalEventPainter(eventPainterParams);
}

return{
width:params.width,
eventSource:eventSource,
timeZone:("timeZone"in params)?params.timeZone:0,
ether:ether,
etherPainter:etherPainter,
eventPainter:eventPainter
};
};

Timeline.createHotZoneBandInfo=function(params){
var theme=("theme"in params)?params.theme:Timeline.getDefaultTheme();

var eventSource=("eventSource"in params)?params.eventSource:null;

var ether=new Timeline.HotZoneEther({
centersOn:("date"in params)?params.date:new Date(),
interval:SimileAjax.DateTime.gregorianUnitLengths[params.intervalUnit],
pixelsPerInterval:params.intervalPixels,
zones:params.zones
});

var etherPainter=new Timeline.HotZoneGregorianEtherPainter({
unit:params.intervalUnit,
zones:params.zones,
theme:theme,
align:("align"in params)?params.align:undefined
});

var eventPainterParams={
showText:("showEventText"in params)?params.showEventText:true,
theme:theme
};
if("trackHeight"in params){
eventPainterParams.trackHeight=params.trackHeight;
}
if("trackGap"in params){
eventPainterParams.trackGap=params.trackGap;
}

var layout=("overview"in params&&params.overview)?"overview":("layout"in params?params.layout:"original");
var eventPainter;
switch(layout){
case"overview":
eventPainter=new Timeline.OverviewEventPainter(eventPainterParams);
break;
case"detailed":
eventPainter=new Timeline.DetailedEventPainter(eventPainterParams);
break;
default:
eventPainter=new Timeline.OriginalEventPainter(eventPainterParams);
}

return{
width:params.width,
eventSource:eventSource,
timeZone:("timeZone"in params)?params.timeZone:0,
ether:ether,
etherPainter:etherPainter,
eventPainter:eventPainter
};
};

Timeline.getDefaultTheme=function(){
if(Timeline._defaultTheme==null){
Timeline._defaultTheme=Timeline.ClassicTheme.create(Timeline.getDefaultLocale());
}
return Timeline._defaultTheme;
};

Timeline.setDefaultTheme=function(theme){
Timeline._defaultTheme=theme;
};

Timeline.loadXML=function(url,f){
var fError=function(statusText,status,xmlhttp){
alert("Failed to load data xml from "+url+"\n"+statusText);
};
var fDone=function(xmlhttp){
var xml=xmlhttp.responseXML;
if(!xml.documentElement&&xmlhttp.responseStream){
xml.load(xmlhttp.responseStream);
}
f(xml,url);
};
SimileAjax.XmlHttp.get(url,fError,fDone);
};


Timeline.loadJSON=function(url,f){
var fError=function(statusText,status,xmlhttp){
alert("Failed to load json data from "+url+"\n"+statusText);
};
var fDone=function(xmlhttp){
f(eval('('+xmlhttp.responseText+')'),url);
};
SimileAjax.XmlHttp.get(url,fError,fDone);
};


Timeline._Impl=function(elmt,bandInfos,orientation,unit){
SimileAjax.WindowManager.initialize();

this._containerDiv=elmt;

this._bandInfos=bandInfos;
this._orientation=orientation==null?Timeline.HORIZONTAL:orientation;
this._unit=(unit!=null)?unit:SimileAjax.NativeDateUnit;

this._initialize();
};

Timeline._Impl.prototype.dispose=function(){
for(var i=0;i<this._bands.length;i++){
this._bands[i].dispose();
}
this._bands=null;
this._bandInfos=null;
this._containerDiv.innerHTML="";
};

Timeline._Impl.prototype.getBandCount=function(){
return this._bands.length;
};

Timeline._Impl.prototype.getBand=function(index){
return this._bands[index];
};

Timeline._Impl.prototype.layout=function(){
this._distributeWidths();
};

Timeline._Impl.prototype.paint=function(){
for(var i=0;i<this._bands.length;i++){
this._bands[i].paint();
}
};

Timeline._Impl.prototype.getDocument=function(){
return this._containerDiv.ownerDocument;
};

Timeline._Impl.prototype.addDiv=function(div){
this._containerDiv.appendChild(div);
};

Timeline._Impl.prototype.removeDiv=function(div){
this._containerDiv.removeChild(div);
};

Timeline._Impl.prototype.isHorizontal=function(){
return this._orientation==Timeline.HORIZONTAL;
};

Timeline._Impl.prototype.isVertical=function(){
return this._orientation==Timeline.VERTICAL;
};

Timeline._Impl.prototype.getPixelLength=function(){
return this._orientation==Timeline.HORIZONTAL?
this._containerDiv.offsetWidth:this._containerDiv.offsetHeight;
};

Timeline._Impl.prototype.getPixelWidth=function(){
return this._orientation==Timeline.VERTICAL?
this._containerDiv.offsetWidth:this._containerDiv.offsetHeight;
};

Timeline._Impl.prototype.getUnit=function(){
return this._unit;
};

Timeline._Impl.prototype.loadXML=function(url,f){
var tl=this;


var fError=function(statusText,status,xmlhttp){
alert("Failed to load data xml from "+url+"\n"+statusText);
tl.hideLoadingMessage();
};
var fDone=function(xmlhttp){
try{
var xml=xmlhttp.responseXML;
if(!xml.documentElement&&xmlhttp.responseStream){
xml.load(xmlhttp.responseStream);
}
f(xml,url);
}finally{
tl.hideLoadingMessage();
}
};

this.showLoadingMessage();
window.setTimeout(function(){SimileAjax.XmlHttp.get(url,fError,fDone);},0);
};

Timeline._Impl.prototype.loadJSON=function(url,f){
var tl=this;


var fError=function(statusText,status,xmlhttp){
alert("Failed to load json data from "+url+"\n"+statusText);
tl.hideLoadingMessage();
};
var fDone=function(xmlhttp){
try{
f(eval('('+xmlhttp.responseText+')'),url);
}finally{
tl.hideLoadingMessage();
}
};

this.showLoadingMessage();
window.setTimeout(function(){SimileAjax.XmlHttp.get(url,fError,fDone);},0);
};

Timeline._Impl.prototype._initialize=function(){
var containerDiv=this._containerDiv;
var doc=containerDiv.ownerDocument;

containerDiv.className=
containerDiv.className.split(" ").concat("timeline-container").join(" ");

while(containerDiv.firstChild){
containerDiv.removeChild(containerDiv.firstChild);
}


var elmtCopyright=SimileAjax.Graphics.createTranslucentImage(Timeline.urlPrefix+(this.isHorizontal()?"images/copyright-vertical.png":"images/copyright.png"));
elmtCopyright.className="timeline-copyright";
elmtCopyright.title="Timeline (c) SIMILE - http://simile.mit.edu/timeline/";
SimileAjax.DOM.registerEvent(elmtCopyright,"click",function(){window.location="http://simile.mit.edu/timeline/";});
containerDiv.appendChild(elmtCopyright);


this._bands=[];
for(var i=0;i<this._bandInfos.length;i++){
var band=new Timeline._Band(this,this._bandInfos[i],i);
this._bands.push(band);
}
this._distributeWidths();


for(var i=0;i<this._bandInfos.length;i++){
var bandInfo=this._bandInfos[i];
if("syncWith"in bandInfo){
this._bands[i].setSyncWithBand(
this._bands[bandInfo.syncWith],
("highlight"in bandInfo)?bandInfo.highlight:false
);
}
}


var message=SimileAjax.Graphics.createMessageBubble(doc);
message.containerDiv.className="timeline-message-container";
containerDiv.appendChild(message.containerDiv);

message.contentDiv.className="timeline-message";
message.contentDiv.innerHTML="<img src='"+Timeline.urlPrefix+"images/progress-running.gif' /> Loading...";

this.showLoadingMessage=function(){message.containerDiv.style.display="block";};
this.hideLoadingMessage=function(){message.containerDiv.style.display="none";};
};

Timeline._Impl.prototype._distributeWidths=function(){
var length=this.getPixelLength();
var width=this.getPixelWidth();
var cumulativeWidth=0;

for(var i=0;i<this._bands.length;i++){
var band=this._bands[i];
var bandInfos=this._bandInfos[i];
var widthString=bandInfos.width;

var x=widthString.indexOf("%");
if(x>0){
var percent=parseInt(widthString.substr(0,x));
var bandWidth=percent*width/100;
}else{
var bandWidth=parseInt(widthString);
}

band.setBandShiftAndWidth(cumulativeWidth,bandWidth);
band.setViewLength(length);

cumulativeWidth+=bandWidth;
}
};


Timeline._Band=function(timeline,bandInfo,index){
this._timeline=timeline;
this._bandInfo=bandInfo;
this._index=index;

this._locale=("locale"in bandInfo)?bandInfo.locale:Timeline.getDefaultLocale();
this._timeZone=("timeZone"in bandInfo)?bandInfo.timeZone:0;
this._labeller=("labeller"in bandInfo)?bandInfo.labeller:
(("createLabeller"in timeline.getUnit())?
timeline.getUnit().createLabeller(this._locale,this._timeZone):
new Timeline.GregorianDateLabeller(this._locale,this._timeZone));

this._dragging=false;
this._changing=false;
this._originalScrollSpeed=5;
this._scrollSpeed=this._originalScrollSpeed;
this._onScrollListeners=[];

var b=this;
this._syncWithBand=null;
this._syncWithBandHandler=function(band){
b._onHighlightBandScroll();
};
this._selectorListener=function(band){
b._onHighlightBandScroll();
};


var inputDiv=this._timeline.getDocument().createElement("div");
inputDiv.className="timeline-band-input";
this._timeline.addDiv(inputDiv);

this._keyboardInput=document.createElement("input");
this._keyboardInput.type="text";
inputDiv.appendChild(this._keyboardInput);
SimileAjax.DOM.registerEventWithObject(this._keyboardInput,"keydown",this,"_onKeyDown");
SimileAjax.DOM.registerEventWithObject(this._keyboardInput,"keyup",this,"_onKeyUp");


this._div=this._timeline.getDocument().createElement("div");
this._div.className="timeline-band timeline-band-"+index;
this._timeline.addDiv(this._div);

SimileAjax.DOM.registerEventWithObject(this._div,"mousedown",this,"_onMouseDown");
SimileAjax.DOM.registerEventWithObject(this._div,"mousemove",this,"_onMouseMove");
SimileAjax.DOM.registerEventWithObject(this._div,"mouseup",this,"_onMouseUp");
SimileAjax.DOM.registerEventWithObject(this._div,"mouseout",this,"_onMouseOut");
SimileAjax.DOM.registerEventWithObject(this._div,"dblclick",this,"_onDblClick");


this._innerDiv=this._timeline.getDocument().createElement("div");
this._innerDiv.className="timeline-band-inner";
this._div.appendChild(this._innerDiv);


this._ether=bandInfo.ether;
bandInfo.ether.initialize(timeline);

this._etherPainter=bandInfo.etherPainter;
bandInfo.etherPainter.initialize(this,timeline);

this._eventSource=bandInfo.eventSource;
if(this._eventSource){
this._eventListener={
onAddMany:function(){b._onAddMany();},
onClear:function(){b._onClear();}
}
this._eventSource.addListener(this._eventListener);
}

this._eventPainter=bandInfo.eventPainter;
bandInfo.eventPainter.initialize(this,timeline);

this._decorators=("decorators"in bandInfo)?bandInfo.decorators:[];
for(var i=0;i<this._decorators.length;i++){
this._decorators[i].initialize(this,timeline);
}
};

Timeline._Band.SCROLL_MULTIPLES=5;

Timeline._Band.prototype.dispose=function(){
this.closeBubble();

if(this._eventSource){
this._eventSource.removeListener(this._eventListener);
this._eventListener=null;
this._eventSource=null;
}

this._timeline=null;
this._bandInfo=null;

this._labeller=null;
this._ether=null;
this._etherPainter=null;
this._eventPainter=null;
this._decorators=null;

this._onScrollListeners=null;
this._syncWithBandHandler=null;
this._selectorListener=null;

this._div=null;
this._innerDiv=null;
this._keyboardInput=null;
};

Timeline._Band.prototype.addOnScrollListener=function(listener){
this._onScrollListeners.push(listener);
};

Timeline._Band.prototype.removeOnScrollListener=function(listener){
for(var i=0;i<this._onScrollListeners.length;i++){
if(this._onScrollListeners[i]==listener){
this._onScrollListeners.splice(i,1);
break;
}
}
};

Timeline._Band.prototype.setSyncWithBand=function(band,highlight){
if(this._syncWithBand){
this._syncWithBand.removeOnScrollListener(this._syncWithBandHandler);
}

this._syncWithBand=band;
this._syncWithBand.addOnScrollListener(this._syncWithBandHandler);
this._highlight=highlight;
this._positionHighlight();
};

Timeline._Band.prototype.getLocale=function(){
return this._locale;
};

Timeline._Band.prototype.getTimeZone=function(){
return this._timeZone;
};

Timeline._Band.prototype.getLabeller=function(){
return this._labeller;
};

Timeline._Band.prototype.getIndex=function(){
return this._index;
};

Timeline._Band.prototype.getEther=function(){
return this._ether;
};

Timeline._Band.prototype.getEtherPainter=function(){
return this._etherPainter;
};

Timeline._Band.prototype.getEventSource=function(){
return this._eventSource;
};

Timeline._Band.prototype.getEventPainter=function(){
return this._eventPainter;
};

Timeline._Band.prototype.layout=function(){
this.paint();
};

Timeline._Band.prototype.paint=function(){
this._etherPainter.paint();
this._paintDecorators();
this._paintEvents();
};

Timeline._Band.prototype.softLayout=function(){
this.softPaint();
};

Timeline._Band.prototype.softPaint=function(){
this._etherPainter.softPaint();
this._softPaintDecorators();
this._softPaintEvents();
};

Timeline._Band.prototype.setBandShiftAndWidth=function(shift,width){
var inputDiv=this._keyboardInput.parentNode;
var middle=shift+Math.floor(width/2);
if(this._timeline.isHorizontal()){
this._div.style.top=shift+"px";
this._div.style.height=width+"px";

inputDiv.style.top=middle+"px";
inputDiv.style.left="-1em";
}else{
this._div.style.left=shift+"px";
this._div.style.width=width+"px";

inputDiv.style.left=middle+"px";
inputDiv.style.top="-1em";
}
};

Timeline._Band.prototype.getViewWidth=function(){
if(this._timeline.isHorizontal()){
return this._div.offsetHeight;
}else{
return this._div.offsetWidth;
}
};

Timeline._Band.prototype.setViewLength=function(length){
this._viewLength=length;
this._recenterDiv();
this._onChanging();
};

Timeline._Band.prototype.getViewLength=function(){
return this._viewLength;
};

Timeline._Band.prototype.getTotalViewLength=function(){
return Timeline._Band.SCROLL_MULTIPLES*this._viewLength;
};

Timeline._Band.prototype.getViewOffset=function(){
return this._viewOffset;
};

Timeline._Band.prototype.getMinDate=function(){
return this._ether.pixelOffsetToDate(this._viewOffset);
};

Timeline._Band.prototype.getMaxDate=function(){
return this._ether.pixelOffsetToDate(this._viewOffset+Timeline._Band.SCROLL_MULTIPLES*this._viewLength);
};

Timeline._Band.prototype.getMinVisibleDate=function(){
return this._ether.pixelOffsetToDate(0);
};

Timeline._Band.prototype.getMaxVisibleDate=function(){
return this._ether.pixelOffsetToDate(this._viewLength);
};

Timeline._Band.prototype.getCenterVisibleDate=function(){
return this._ether.pixelOffsetToDate(this._viewLength/2);
};

Timeline._Band.prototype.setMinVisibleDate=function(date){
if(!this._changing){
this._moveEther(Math.round(-this._ether.dateToPixelOffset(date)));
}
};

Timeline._Band.prototype.setMaxVisibleDate=function(date){
if(!this._changing){
this._moveEther(Math.round(this._viewLength-this._ether.dateToPixelOffset(date)));
}
};

Timeline._Band.prototype.setCenterVisibleDate=function(date){
if(!this._changing){
this._moveEther(Math.round(this._viewLength/2-this._ether.dateToPixelOffset(date)));
}
};

Timeline._Band.prototype.dateToPixelOffset=function(date){
return this._ether.dateToPixelOffset(date)-this._viewOffset;
};

Timeline._Band.prototype.pixelOffsetToDate=function(pixels){
return this._ether.pixelOffsetToDate(pixels+this._viewOffset);
};

Timeline._Band.prototype.createLayerDiv=function(zIndex,className){
var div=this._timeline.getDocument().createElement("div");
div.className="timeline-band-layer"+(typeof className=="string"?(" "+className):"");
div.style.zIndex=zIndex;
this._innerDiv.appendChild(div);

var innerDiv=this._timeline.getDocument().createElement("div");
innerDiv.className="timeline-band-layer-inner";
if(SimileAjax.Platform.browser.isIE){
innerDiv.style.cursor="move";
}else{
innerDiv.style.cursor="-moz-grab";
}
div.appendChild(innerDiv);

return innerDiv;
};

Timeline._Band.prototype.removeLayerDiv=function(div){
this._innerDiv.removeChild(div.parentNode);
};

Timeline._Band.prototype.scrollToCenter=function(date,f){
var pixelOffset=this._ether.dateToPixelOffset(date);
if(pixelOffset<-this._viewLength/2){
this.setCenterVisibleDate(this.pixelOffsetToDate(pixelOffset+this._viewLength));
}else if(pixelOffset>3*this._viewLength/2){
this.setCenterVisibleDate(this.pixelOffsetToDate(pixelOffset-this._viewLength));
}
this._autoScroll(Math.round(this._viewLength/2-this._ether.dateToPixelOffset(date)),f);
};

Timeline._Band.prototype.showBubbleForEvent=function(eventID){
var evt=this.getEventSource().getEvent(eventID);
if(evt){
var self=this;
this.scrollToCenter(evt.getStart(),function(){
self._eventPainter.showBubble(evt);
});
}
};

Timeline._Band.prototype._onMouseDown=function(innerFrame,evt,target){
this.closeBubble();

this._dragging=true;
this._dragX=evt.clientX;
this._dragY=evt.clientY;
};

Timeline._Band.prototype._onMouseMove=function(innerFrame,evt,target){
if(this._dragging){
var diffX=evt.clientX-this._dragX;
var diffY=evt.clientY-this._dragY;

this._dragX=evt.clientX;
this._dragY=evt.clientY;

this._moveEther(this._timeline.isHorizontal()?diffX:diffY);
this._positionHighlight();
}
};

Timeline._Band.prototype._onMouseUp=function(innerFrame,evt,target){
this._dragging=false;
this._keyboardInput.focus();
};

Timeline._Band.prototype._onMouseOut=function(innerFrame,evt,target){
var coords=SimileAjax.DOM.getEventRelativeCoordinates(evt,innerFrame);
coords.x+=this._viewOffset;
if(coords.x<0||coords.x>innerFrame.offsetWidth||
coords.y<0||coords.y>innerFrame.offsetHeight){
this._dragging=false;
}
};

Timeline._Band.prototype._onDblClick=function(innerFrame,evt,target){
var coords=SimileAjax.DOM.getEventRelativeCoordinates(evt,innerFrame);
var distance=coords.x-(this._viewLength/2-this._viewOffset);

this._autoScroll(-distance);
};

Timeline._Band.prototype._onKeyDown=function(keyboardInput,evt,target){
if(!this._dragging){
switch(evt.keyCode){
case 27:
break;
case 37:
case 38:
this._scrollSpeed=Math.min(50,Math.abs(this._scrollSpeed*1.05));
this._moveEther(this._scrollSpeed);
break;
case 39:
case 40:
this._scrollSpeed=-Math.min(50,Math.abs(this._scrollSpeed*1.05));
this._moveEther(this._scrollSpeed);
break;
default:
return true;
}
this.closeBubble();

SimileAjax.DOM.cancelEvent(evt);
return false;
}
return true;
};

Timeline._Band.prototype._onKeyUp=function(keyboardInput,evt,target){
if(!this._dragging){
this._scrollSpeed=this._originalScrollSpeed;

switch(evt.keyCode){
case 35:
this.setCenterVisibleDate(this._eventSource.getLatestDate());
break;
case 36:
this.setCenterVisibleDate(this._eventSource.getEarliestDate());
break;
case 33:
this._autoScroll(this._timeline.getPixelLength());
break;
case 34:
this._autoScroll(-this._timeline.getPixelLength());
break;
default:
return true;
}

this.closeBubble();

SimileAjax.DOM.cancelEvent(evt);
return false;
}
return true;
};

Timeline._Band.prototype._autoScroll=function(distance,f){
var b=this;
var a=SimileAjax.Graphics.createAnimation(
function(abs,diff){
b._moveEther(diff);
},
0,
distance,
1000,
f
);
a.run();
};

Timeline._Band.prototype._moveEther=function(shift){
this.closeBubble();

this._viewOffset+=shift;
this._ether.shiftPixels(-shift);
if(this._timeline.isHorizontal()){
this._div.style.left=this._viewOffset+"px";
}else{
this._div.style.top=this._viewOffset+"px";
}

if(this._viewOffset>-this._viewLength*0.5||
this._viewOffset<-this._viewLength*(Timeline._Band.SCROLL_MULTIPLES-1.5)){

this._recenterDiv();
}else{
this.softLayout();
}

this._onChanging();
}

Timeline._Band.prototype._onChanging=function(){
this._changing=true;

this._fireOnScroll();
this._setSyncWithBandDate();

this._changing=false;
};

Timeline._Band.prototype._fireOnScroll=function(){
for(var i=0;i<this._onScrollListeners.length;i++){
this._onScrollListeners[i](this);
}
};

Timeline._Band.prototype._setSyncWithBandDate=function(){
if(this._syncWithBand){
var centerDate=this._ether.pixelOffsetToDate(this.getViewLength()/2);
this._syncWithBand.setCenterVisibleDate(centerDate);
}
};

Timeline._Band.prototype._onHighlightBandScroll=function(){
if(this._syncWithBand){
var centerDate=this._syncWithBand.getCenterVisibleDate();
var centerPixelOffset=this._ether.dateToPixelOffset(centerDate);

this._moveEther(Math.round(this._viewLength/2-centerPixelOffset));

if(this._highlight){
this._etherPainter.setHighlight(
this._syncWithBand.getMinVisibleDate(),
this._syncWithBand.getMaxVisibleDate());
}
}
};

Timeline._Band.prototype._onAddMany=function(){
this._paintEvents();
};

Timeline._Band.prototype._onClear=function(){
this._paintEvents();
};

Timeline._Band.prototype._positionHighlight=function(){
if(this._syncWithBand){
var startDate=this._syncWithBand.getMinVisibleDate();
var endDate=this._syncWithBand.getMaxVisibleDate();

if(this._highlight){
this._etherPainter.setHighlight(startDate,endDate);
}
}
};

Timeline._Band.prototype._recenterDiv=function(){
this._viewOffset=-this._viewLength*(Timeline._Band.SCROLL_MULTIPLES-1)/2;
if(this._timeline.isHorizontal()){
this._div.style.left=this._viewOffset+"px";
this._div.style.width=(Timeline._Band.SCROLL_MULTIPLES*this._viewLength)+"px";
}else{
this._div.style.top=this._viewOffset+"px";
this._div.style.height=(Timeline._Band.SCROLL_MULTIPLES*this._viewLength)+"px";
}
this.layout();
};

Timeline._Band.prototype._paintEvents=function(){
this._eventPainter.paint();
};

Timeline._Band.prototype._softPaintEvents=function(){
this._eventPainter.softPaint();
};

Timeline._Band.prototype._paintDecorators=function(){
for(var i=0;i<this._decorators.length;i++){
this._decorators[i].paint();
}
};

Timeline._Band.prototype._softPaintDecorators=function(){
for(var i=0;i<this._decorators.length;i++){
this._decorators[i].softPaint();
}
};

Timeline._Band.prototype.closeBubble=function(){
SimileAjax.WindowManager.cancelPopups();
};


/* units.js */





Timeline.NativeDateUnit=new Object();

Timeline.NativeDateUnit.createLabeller=function(locale,timeZone){
return new Timeline.GregorianDateLabeller(locale,timeZone);
};


Timeline.NativeDateUnit.makeDefaultValue=function(){
return new Date();
};

Timeline.NativeDateUnit.cloneValue=function(v){
return new Date(v.getTime());
};

Timeline.NativeDateUnit.getParser=function(format){
if(typeof format=="string"){
format=format.toLowerCase();
}
return(format=="iso8601"||format=="iso 8601")?

Timeline.DateTime.parseIso8601DateTime:

Timeline.DateTime.parseGregorianDateTime;

};

Timeline.NativeDateUnit.parseFromObject=function(o){
return Timeline.DateTime.parseGregorianDateTime(o);
};


Timeline.NativeDateUnit.toNumber=function(v){
return v.getTime();
};

Timeline.NativeDateUnit.fromNumber=function(n){
return new Date(n);
};

Timeline.NativeDateUnit.compare=function(v1,v2){
var n1,n2;
if(typeof v1=="object"){
n1=v1.getTime();
}else{
n1=Number(v1);
}
if(typeof v2=="object"){
n2=v2.getTime();
}else{
n2=Number(v2);
}

return n1-n2;
};

Timeline.NativeDateUnit.earlier=function(v1,v2){
return Timeline.NativeDateUnit.compare(v1,v2)<0?v1:v2;
};

Timeline.NativeDateUnit.later=function(v1,v2){
return Timeline.NativeDateUnit.compare(v1,v2)>0?v1:v2;
};

Timeline.NativeDateUnit.change=function(v,n){
return new Date(v.getTime()+n);
};

