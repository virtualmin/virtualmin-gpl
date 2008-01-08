

/* timeplot.js */



Timeline.Debug=SimileAjax.Debug;
var log=SimileAjax.Debug.log;


Object.extend=function(destination,source){
for(var property in source){
destination[property]=source[property];
}
return destination;
}




Timeplot.create=function(elmt,plotInfos){
return new Timeplot._Impl(elmt,plotInfos);
};


Timeplot.createPlotInfo=function(params){
return{
id:("id"in params)?params.id:"p"+Math.round(Math.random()*1000000),
dataSource:("dataSource"in params)?params.dataSource:null,
eventSource:("eventSource"in params)?params.eventSource:null,
timeGeometry:("timeGeometry"in params)?params.timeGeometry:new Timeplot.DefaultTimeGeometry(),
valueGeometry:("valueGeometry"in params)?params.valueGeometry:new Timeplot.DefaultValueGeometry(),
timeZone:("timeZone"in params)?params.timeZone:0,
fillColor:("fillColor"in params)?((params.fillColor=="string")?new Timeplot.Color(params.fillColor):params.fillColor):null,
fillGradient:("fillGradient"in params)?params.fillGradient:true,
fillFrom:("fillFrom"in params)?params.fillFrom:Number.NEGATIVE_INFINITY,
lineColor:("lineColor"in params)?((params.lineColor=="string")?new Timeplot.Color(params.lineColor):params.lineColor):new Timeplot.Color("#606060"),
lineWidth:("lineWidth"in params)?params.lineWidth:1.0,
dotRadius:("dotRadius"in params)?params.dotRadius:2.0,
dotColor:("dotColor"in params)?params.dotColor:null,
eventLineWidth:("eventLineWidth"in params)?params.eventLineWidth:1.0,
showValues:("showValues"in params)?params.showValues:false,
roundValues:("roundValues"in params)?params.roundValues:true,
valuesOpacity:("valuesOpacity"in params)?params.valuesOpacity:75,
bubbleWidth:("bubbleWidth"in params)?params.bubbleWidth:300,
bubbleHeight:("bubbleHeight"in params)?params.bubbleHeight:200
};
};




Timeplot._Impl=function(elmt,plotInfos){
this._id="t"+Math.round(Math.random()*1000000);
this._containerDiv=elmt;
this._plotInfos=plotInfos;
this._painters={
background:[],
foreground:[]
};
this._painter=null;
this._active=false;
this._upright=false;
this._initialize();
};

Timeplot._Impl.prototype={

dispose:function(){
for(var i=0;i<this._plots.length;i++){
this._plots[i].dispose();
}
this._plots=null;
this._plotsInfos=null;
this._containerDiv.innerHTML="";
},


getElement:function(){
return this._containerDiv;
},


getDocument:function(){
return this._containerDiv.ownerDocument;
},


add:function(div){
this._containerDiv.appendChild(div);
},


remove:function(div){
this._containerDiv.removeChild(div);
},


addPainter:function(layerName,painter){
var layer=this._painters[layerName];
if(layer){
for(var i=0;i<layer.length;i++){
if(layer[i].context._id==painter.context._id){
return;
}
}
layer.push(painter);
}
},


removePainter:function(layerName,painter){
var layer=this._painters[layerName];
if(layer){
for(var i=0;i<layer.length;i++){
if(layer[i].context._id==painter.context._id){
layer.splice(i,1);
break;
}
}
}
},


getWidth:function(){
return this._containerDiv.clientWidth;
},


getHeight:function(){
return this._containerDiv.clientHeight;
},


getCanvas:function(){
return this._canvas;
},


loadText:function(url,separator,eventSource,filter){
if(this._active){
var tp=this;

var fError=function(statusText,status,xmlhttp){
alert("Failed to load data xml from "+url+"\n"+statusText);
tp.hideLoadingMessage();
};

var fDone=function(xmlhttp){
try{
eventSource.loadText(xmlhttp.responseText,separator,url,filter);
}catch(e){
SimileAjax.Debug.exception(e);
}finally{
tp.hideLoadingMessage();
}
};

this.showLoadingMessage();
window.setTimeout(function(){SimileAjax.XmlHttp.get(url,fError,fDone);},0);
}
},


loadXML:function(url,eventSource){
if(this._active){
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
eventSource.loadXML(xml,url);
}finally{
tl.hideLoadingMessage();
}
};

this.showLoadingMessage();
window.setTimeout(function(){SimileAjax.XmlHttp.get(url,fError,fDone);},0);
}
},


putText:function(id,text,clazz,styles){
var div=this.putDiv(id,"timeplot-div "+clazz,styles);
div.innerHTML=text;
return div;
},


putDiv:function(id,clazz,styles){
var tid=this._id+"-"+id;
var div=document.getElementById(tid);
if(!div){
var container=this._containerDiv.firstChild;
div=document.createElement("div");
div.setAttribute("id",tid);
container.appendChild(div);
}
div.setAttribute("class","timeplot-div "+clazz);
div.setAttribute("className","timeplot-div "+clazz);
this.placeDiv(div,styles);
return div;
},


placeDiv:function(div,styles){
if(styles){
for(style in styles){
if(style=="left"){
styles[style]+=this._paddingX;
styles[style]+="px";
}else if(style=="right"){
styles[style]+=this._paddingX;
styles[style]+="px";
}else if(style=="top"){
styles[style]+=this._paddingY;
styles[style]+="px";
}else if(style=="bottom"){
styles[style]+=this._paddingY;
styles[style]+="px";
}else if(style=="width"){
if(styles[style]<0)styles[style]=0;
styles[style]+="px";
}else if(style=="height"){
if(styles[style]<0)styles[style]=0;
styles[style]+="px";
}
div.style[style]=styles[style];
}
}
},


locate:function(div){
return{
x:div.offsetLeft-this._paddingX,
y:div.offsetTop-this._paddingY
}
},


update:function(){
if(this._active){
for(var i=0;i<this._plots.length;i++){
var plot=this._plots[i];
var dataSource=plot.getDataSource();
if(dataSource){
var range=dataSource.getRange();
if(range){
plot._valueGeometry.setRange(range);
plot._timeGeometry.setRange(range);
}
}
}
this.paint();
}
},


repaint:function(){
if(this._active){
this._prepareCanvas();
for(var i=0;i<this._plots.length;i++){
var plot=this._plots[i];
if(plot._timeGeometry)plot._timeGeometry.reset();
if(plot._valueGeometry)plot._valueGeometry.reset();
}
this.paint();
}
},


paint:function(){
if(this._active&&this._painter==null){
var timeplot=this;
this._painter=window.setTimeout(function(){
timeplot._clearCanvas();

var run=function(action,context){
try{
if(context.setTimeplot)context.setTimeplot(timeplot);
action.apply(context,[]);
}catch(e){
SimileAjax.Debug.exception(e);
}
}

var background=timeplot._painters.background;
for(var i=0;i<background.length;i++){
run(background[i].action,background[i].context);
}
var foreground=timeplot._painters.foreground;
for(var i=0;i<foreground.length;i++){
run(foreground[i].action,foreground[i].context);
}

timeplot._painter=null;
},20);
}
},

_clearCanvas:function(){
var canvas=this.getCanvas();
var ctx=canvas.getContext('2d');
ctx.clearRect(0,0,canvas.width,canvas.height);
},

_prepareCanvas:function(){
var canvas=this.getCanvas();




var con=$('#'+this._containerDiv.id);
this._paddingX=(parseInt(con.css('paddingLeft'))+
parseInt(con.css('paddingRight')))/2;
this._paddingY=(parseInt(con.css('paddingTop'))+
parseInt(con.css('paddingBottom')))/2;

canvas.width=this.getWidth()-(this._paddingX*2);
canvas.height=this.getHeight()-(this._paddingY*2);

var ctx=canvas.getContext('2d');
this._setUpright(ctx,canvas);
ctx.globalCompositeOperation='source-over';
},

_setUpright:function(ctx,canvas){


if(!SimileAjax.Platform.browser.isIE)this._upright=false;
if(!this._upright){
this._upright=true;
ctx.translate(0,canvas.height);
ctx.scale(1,-1);
}
},

_isBrowserSupported:function(canvas){
var browser=SimileAjax.Platform.browser;
if((canvas.getContext&&window.getComputedStyle)||
(browser.isIE&&browser.majorVersion>=6)){
return true;
}else{
return false;
}
},

_initialize:function(){



SimileAjax.WindowManager.initialize();

var containerDiv=this._containerDiv;
var doc=containerDiv.ownerDocument;


containerDiv.className="timeplot-container "+containerDiv.className;


while(containerDiv.firstChild){
containerDiv.removeChild(containerDiv.firstChild);
}

var canvas=doc.createElement("canvas");

if(this._isBrowserSupported(canvas)){

var labels=doc.createElement("div");
containerDiv.appendChild(labels);

this._canvas=canvas;
canvas.className="timeplot-canvas";
containerDiv.appendChild(canvas);
if(!canvas.getContext&&G_vmlCanvasManager){
canvas=G_vmlCanvasManager.initElement(this._canvas);
this._canvas=canvas;
}
this._prepareCanvas();


var elmtCopyright=SimileAjax.Graphics.createTranslucentImage(Timeplot.urlPrefix+"images/copyright.png");
elmtCopyright.className="timeplot-copyright";
elmtCopyright.title="Timeplot (c) SIMILE - http://simile.mit.edu/timeplot/";
SimileAjax.DOM.registerEvent(elmtCopyright,"click",function(){window.location="http://simile.mit.edu/timeplot/";});
containerDiv.appendChild(elmtCopyright);

var timeplot=this;
var painter={
onAddMany:function(){timeplot.update();},
onClear:function(){timeplot.update();}
}


this._plots=[];
if(this._plotInfos){
for(var i=0;i<this._plotInfos.length;i++){
var plot=new Timeplot.Plot(this,this._plotInfos[i]);
var dataSource=plot.getDataSource();
if(dataSource){
dataSource.addListener(painter);
}
this.addPainter("background",{
context:plot.getTimeGeometry(),
action:plot.getTimeGeometry().paint
});
this.addPainter("background",{
context:plot.getValueGeometry(),
action:plot.getValueGeometry().paint
});
this.addPainter("foreground",{
context:plot,
action:plot.paint
});
this._plots.push(plot);
plot.initialize();
}
}


var message=SimileAjax.Graphics.createMessageBubble(doc);
message.containerDiv.className="timeplot-message-container";
containerDiv.appendChild(message.containerDiv);

message.contentDiv.className="timeplot-message";
message.contentDiv.innerHTML="<img src='"+Timeplot.urlPrefix+"images/progress-running.gif' /> Loading...";

this.showLoadingMessage=function(){message.containerDiv.style.display="block";};
this.hideLoadingMessage=function(){message.containerDiv.style.display="none";};

this._active=true;

}else{

this._message=SimileAjax.Graphics.createMessageBubble(doc);
this._message.containerDiv.className="timeplot-message-container";
this._message.containerDiv.style.top="15%";
this._message.containerDiv.style.left="20%";
this._message.containerDiv.style.right="20%";
this._message.containerDiv.style.minWidth="20em";
this._message.contentDiv.className="timeplot-message";
this._message.contentDiv.innerHTML="We're terribly sorry, but your browser is not currently supported by <a href='http://simile.mit.edu/timeplot/'>Timeplot</a>.<br><br> We are working on supporting it in the near future but, for now, see the <a href='http://simile.mit.edu/wiki/Timeplot_Limitations'>list of currently supported browsers</a>.";
this._message.containerDiv.style.display="block";

containerDiv.appendChild(this._message.containerDiv);

}
}
};


/* plot.js */




Timeplot.Plot=function(timeplot,plotInfo){
this._timeplot=timeplot;
this._canvas=timeplot.getCanvas();
this._plotInfo=plotInfo;
this._id=plotInfo.id;
this._timeGeometry=plotInfo.timeGeometry;
this._valueGeometry=plotInfo.valueGeometry;
this._showValues=plotInfo.showValues;
this._theme=new Timeline.getDefaultTheme();
this._dataSource=plotInfo.dataSource;
this._eventSource=plotInfo.eventSource;
this._bubble=null;
};

Timeplot.Plot.prototype={


initialize:function(){
if(this._showValues&&this._dataSource&&this._dataSource.getValue){
this._timeFlag=this._timeplot.putDiv("timeflag","timeplot-timeflag");
this._valueFlag=this._timeplot.putDiv(this._id+"valueflag","timeplot-valueflag");
this._valueFlagLineLeft=this._timeplot.putDiv(this._id+"valueflagLineLeft","timeplot-valueflag-line");
this._valueFlagLineRight=this._timeplot.putDiv(this._id+"valueflagLineRight","timeplot-valueflag-line");
if(!this._valueFlagLineLeft.firstChild){
this._valueFlagLineLeft.appendChild(SimileAjax.Graphics.createTranslucentImage(Timeplot.urlPrefix+"images/line_left.png"));
this._valueFlagLineRight.appendChild(SimileAjax.Graphics.createTranslucentImage(Timeplot.urlPrefix+"images/line_right.png"));
}
this._valueFlagPole=this._timeplot.putDiv(this._id+"valuepole","timeplot-valueflag-pole");

var opacity=this._plotInfo.valuesOpacity;

SimileAjax.Graphics.setOpacity(this._timeFlag,opacity);
SimileAjax.Graphics.setOpacity(this._valueFlag,opacity);
SimileAjax.Graphics.setOpacity(this._valueFlagLineLeft,opacity);
SimileAjax.Graphics.setOpacity(this._valueFlagLineRight,opacity);
SimileAjax.Graphics.setOpacity(this._valueFlagPole,opacity);

var plot=this;

var mouseOverHandler=function(elmt,evt,target){
plot._valueFlag.style.display="block";
mouseMoveHandler(elmt,evt,target);
}

var day=24*60*60*1000;
var month=30*day;

var mouseMoveHandler=function(elmt,evt,target){
if(typeof SimileAjax!="undefined"){
var c=plot._canvas;
var x=Math.round(SimileAjax.DOM.getEventRelativeCoordinates(evt,plot._canvas).x);
if(x>c.width)x=c.width;
if(isNaN(x)||x<0)x=0;
var t=plot._timeGeometry.fromScreen(x);
if(t==0){
plot._valueFlag.style.display="none";
return;
}

var v=plot._dataSource.getValue(t);
if(plot._plotInfo.roundValues)v=Math.round(v);
plot._valueFlag.innerHTML=new String(v);
var d=new Date(t);
var p=plot._timeGeometry.getPeriod();
if(p<day){
plot._timeFlag.innerHTML=d.toLocaleTimeString();
}else if(p>month){
plot._timeFlag.innerHTML=d.toLocaleDateString();
}else{
plot._timeFlag.innerHTML=d.toLocaleString();
}

var tw=plot._timeFlag.clientWidth;
var th=plot._timeFlag.clientHeight;
var tdw=Math.round(tw/2);
var vw=plot._valueFlag.clientWidth;
var vh=plot._valueFlag.clientHeight;
var y=plot._valueGeometry.toScreen(v);

if(x+tdw>c.width){
var tx=c.width-tdw;
}else if(x-tdw<0){
var tx=tdw;
}else{
var tx=x;
}

if(plot._timeGeometry._timeValuePosition=="top"){
plot._timeplot.placeDiv(plot._valueFlagPole,{
left:x,
top:th-5,
height:c.height-y-th+6,
display:"block"
});
plot._timeplot.placeDiv(plot._timeFlag,{
left:tx-tdw,
top:-6,
display:"block"
});
}else{
plot._timeplot.placeDiv(plot._valueFlagPole,{
left:x,
bottom:th-5,
height:y-th+6,
display:"block"
});
plot._timeplot.placeDiv(plot._timeFlag,{
left:tx-tdw,
bottom:-6,
display:"block"
});
}

if(x+vw+14>c.width&&y+vh+4>c.height){
plot._valueFlagLineLeft.style.display="none";
plot._timeplot.placeDiv(plot._valueFlagLineRight,{
left:x-14,
bottom:y-14,
display:"block"
});
plot._timeplot.placeDiv(plot._valueFlag,{
left:x-vw-13,
bottom:y-vh-13,
display:"block"
});
}else if(x+vw+14>c.width&&y+vh+4<c.height){
plot._valueFlagLineRight.style.display="none";
plot._timeplot.placeDiv(plot._valueFlagLineLeft,{
left:x-14,
bottom:y,
display:"block"
});
plot._timeplot.placeDiv(plot._valueFlag,{
left:x-vw-13,
bottom:y+13,
display:"block"
});
}else if(x+vw+14<c.width&&y+vh+4>c.height){
plot._valueFlagLineRight.style.display="none";
plot._timeplot.placeDiv(plot._valueFlagLineLeft,{
left:x,
bottom:y-13,
display:"block"
});
plot._timeplot.placeDiv(plot._valueFlag,{
left:x+13,
bottom:y-13,
display:"block"
});
}else{
plot._valueFlagLineLeft.style.display="none";
plot._timeplot.placeDiv(plot._valueFlagLineRight,{
left:x,
bottom:y,
display:"block"
});
plot._timeplot.placeDiv(plot._valueFlag,{
left:x+13,
bottom:y+13,
display:"block"
});
}
}
}

var timeplotElement=this._timeplot.getElement();
SimileAjax.DOM.registerEvent(timeplotElement,"mouseover",mouseOverHandler);
SimileAjax.DOM.registerEvent(timeplotElement,"mousemove",mouseMoveHandler);
}
},


dispose:function(){
if(this._dataSource){
this._dataSource.removeListener(this._paintingListener);
this._paintingListener=null;
this._dataSource.dispose();
this._dataSource=null;
}
},


getDataSource:function(){
return(this._dataSource)?this._dataSource:this._eventSource;
},


getTimeGeometry:function(){
return this._timeGeometry;
},


getValueGeometry:function(){
return this._valueGeometry;
},


paint:function(){
var ctx=this._canvas.getContext('2d');

ctx.lineWidth=this._plotInfo.lineWidth;
ctx.lineJoin='miter';

if(this._dataSource){
if(this._plotInfo.fillColor){
if(this._plotInfo.fillGradient){
var gradient=ctx.createLinearGradient(0,this._canvas.height,0,0);
gradient.addColorStop(0,this._plotInfo.fillColor.toString());
gradient.addColorStop(0.5,this._plotInfo.fillColor.toString());
gradient.addColorStop(1,'rgba(255,255,255,0)');

ctx.fillStyle=gradient;
}else{
ctx.fillStyle=this._plotInfo.fillColor.toString();
}

ctx.beginPath();
ctx.moveTo(0,0);
this._plot(function(x,y){
ctx.lineTo(x,y);
});
if(this._plotInfo.fillFrom==Number.NEGATIVE_INFINITY){
ctx.lineTo(this._canvas.width,0);
}else if(this._plotInfo.fillFrom==Number.POSITIVE_INFINITY){
ctx.lineTo(this._canvas.width,this._canvas.height);
ctx.lineTo(0,this._canvas.height);
}else{
ctx.lineTo(this._canvas.width,this._valueGeometry.toScreen(this._plotInfo.fillFrom));
ctx.lineTo(0,this._valueGeometry.toScreen(this._plotInfo.fillFrom));
}
ctx.fill();
}

if(this._plotInfo.lineColor){
ctx.strokeStyle=this._plotInfo.lineColor.toString();
ctx.beginPath();
var first=true;
this._plot(function(x,y){
if(first){
first=false;
ctx.moveTo(x,y);
}
ctx.lineTo(x,y);
});
ctx.stroke();
}

if(this._plotInfo.dotColor){
ctx.fillStyle=this._plotInfo.dotColor.toString();
var r=this._plotInfo.dotRadius;
this._plot(function(x,y){
ctx.beginPath();
ctx.arc(x,y,r,0,2*Math.PI,true);
ctx.fill();
});
}
}

if(this._eventSource){
var gradient=ctx.createLinearGradient(0,0,0,this._canvas.height);
gradient.addColorStop(1,'rgba(255,255,255,0)');

ctx.strokeStyle=gradient;
ctx.fillStyle=gradient;
ctx.lineWidth=this._plotInfo.eventLineWidth;
ctx.lineJoin='miter';

var i=this._eventSource.getAllEventIterator();
while(i.hasNext()){
var event=i.next();
var color=event.getColor();
color=(color)?new Timeplot.Color(color):this._plotInfo.lineColor;
var eventStart=event.getStart().getTime();
var eventEnd=event.getEnd().getTime();
if(eventStart==eventEnd){
var c=color.toString();
gradient.addColorStop(0,c);
var start=this._timeGeometry.toScreen(eventStart);
start=Math.floor(start)+0.5;
var end=start;
ctx.beginPath();
ctx.moveTo(start,0);
ctx.lineTo(start,this._canvas.height);
ctx.stroke();
var x=start-4;
var w=7;
}else{
var c=color.toString(0.5);
gradient.addColorStop(0,c);
var start=this._timeGeometry.toScreen(eventStart);
start=Math.floor(start)+0.5;
var end=this._timeGeometry.toScreen(eventEnd);
end=Math.floor(end)+0.5;
ctx.fillRect(start,0,end-start,this._canvas.height);
var x=start;
var w=end-start-1;
}

var div=this._timeplot.putDiv(event.getID(),"timeplot-event-box",{
left:Math.round(x),
width:Math.round(w),
top:0,
height:this._canvas.height-1
});

var plot=this;
var clickHandler=function(event){
return function(elmt,evt,target){
var doc=plot._timeplot.getDocument();
plot._closeBubble();
var coords=SimileAjax.DOM.getEventPageCoordinates(evt);
var elmtCoords=SimileAjax.DOM.getPageCoordinates(elmt);
plot._bubble=SimileAjax.Graphics.createBubbleForPoint(coords.x,elmtCoords.top+plot._canvas.height,plot._plotInfo.bubbleWidth,plot._plotInfo.bubbleHeight,"bottom");
event.fillInfoBubble(plot._bubble.content,plot._theme,plot._timeGeometry.getLabeler());
}
};
var mouseOverHandler=function(elmt,evt,target){
elmt.oldClass=elmt.className;
elmt.className=elmt.className+" timeplot-event-box-highlight";
};
var mouseOutHandler=function(elmt,evt,target){
elmt.className=elmt.oldClass;
elmt.oldClass=null;
}

if(!div.instrumented){
SimileAjax.DOM.registerEvent(div,"click",clickHandler(event));
SimileAjax.DOM.registerEvent(div,"mouseover",mouseOverHandler);
SimileAjax.DOM.registerEvent(div,"mouseout",mouseOutHandler);
div.instrumented=true;
}
}
}
},

_plot:function(f){
var data=this._dataSource.getData();
if(data){
var times=data.times;
var values=data.values;
var T=times.length;
for(var t=0;t<T;t++){
var x=this._timeGeometry.toScreen(times[t]);
var y=this._valueGeometry.toScreen(values[t]);
f(x,y);
}
}
},

_closeBubble:function(){
if(this._bubble!=null){
this._bubble.close();
this._bubble=null;
}
}

}

/* sources.js */




Timeplot.DefaultEventSource=function(eventIndex){
Timeline.DefaultEventSource.apply(this,arguments);
};

Object.extend(Timeplot.DefaultEventSource.prototype,Timeline.DefaultEventSource.prototype);


Timeplot.DefaultEventSource.prototype.loadText=function(text,separator,url,filter){

if(text==null){
return;
}

this._events.maxValues=new Array();
var base=this._getBaseURL(url);

var dateTimeFormat='iso8601';
var parseDateTimeFunction=this._events.getUnit().getParser(dateTimeFormat);

var data=this._parseText(text,separator);

var added=false;

if(filter){
data=filter(data);
}

if(data){
for(var i=0;i<data.length;i++){
var row=data[i];
if(row.length>1){
var evt=new Timeplot.DefaultEventSource.NumericEvent(
parseDateTimeFunction(row[0]),
row.slice(1)
);
this._events.add(evt);
added=true;
}
}
}

if(added){
this._fire("onAddMany",[]);
}
}


Timeplot.DefaultEventSource.prototype._parseText=function(text,separator){
text=text.replace(/\r\n?/g,"\n");
var pos=0;
var len=text.length;
var table=[];
while(pos<len){
var line=[];
if(text.charAt(pos)!='#'){
while(pos<len){
if(text.charAt(pos)=='"'){
var nextquote=text.indexOf('"',pos+1);
while(nextquote<len&&nextquote>-1){
if(text.charAt(nextquote+1)!='"'){
break;
}
nextquote=text.indexOf('"',nextquote+2);
}
if(nextquote<0){

}else if(text.charAt(nextquote+1)==separator){
var quoted=text.substr(pos+1,nextquote-pos-1);
quoted=quoted.replace(/""/g,'"');
line[line.length]=quoted;
pos=nextquote+2;
continue;
}else if(text.charAt(nextquote+1)=="\n"||
len==nextquote+1){
var quoted=text.substr(pos+1,nextquote-pos-1);
quoted=quoted.replace(/""/g,'"');
line[line.length]=quoted;
pos=nextquote+2;
break;
}else{

}
}
var nextseparator=text.indexOf(separator,pos);
var nextnline=text.indexOf("\n",pos);
if(nextnline<0)nextnline=len;
if(nextseparator>-1&&nextseparator<nextnline){
line[line.length]=text.substr(pos,nextseparator-pos);
pos=nextseparator+1;
}else{
line[line.length]=text.substr(pos,nextnline-pos);
pos=nextnline+1;
break;
}
}
}else{
var nextnline=text.indexOf("\n",pos);
pos=(nextnline>-1)?nextnline+1:cur;
}
if(line.length>0){
table[table.length]=line;
}
}
if(table.length<0)return;
return table;
}


Timeplot.DefaultEventSource.prototype.getRange=function(){
var earliestDate=this.getEarliestDate();
var latestDate=this.getLatestDate();
return{
earliestDate:(earliestDate)?earliestDate:null,
latestDate:(latestDate)?latestDate:null,
min:0,
max:0
};
}




Timeplot.DefaultEventSource.NumericEvent=function(time,values){
this._id="e"+Math.round(Math.random()*1000000);
this._time=time;
this._values=values;
};

Timeplot.DefaultEventSource.NumericEvent.prototype={
getID:function(){return this._id;},
getTime:function(){return this._time;},
getValues:function(){return this._values;},


getStart:function(){return this._time;},
getEnd:function(){return this._time;}
};




Timeplot.DataSource=function(eventSource){
this._eventSource=eventSource;
var source=this;
this._processingListener={
onAddMany:function(){source._process();},
onClear:function(){source._clear();}
}
this.addListener(this._processingListener);
this._listeners=[];
this._data=null;
this._range=null;
};

Timeplot.DataSource.prototype={

_clear:function(){
this._data=null;
this._range=null;
},

_process:function(){
this._data={
times:new Array(),
values:new Array()
};
this._range={
earliestDate:null,
latestDate:null,
min:0,
max:0
};
},


getRange:function(){
return this._range;
},


getData:function(){
return this._data;
},


getValue:function(t){
if(this._data){
for(var i=0;i<this._data.times.length;i++){
var l=this._data.times[i];
if(l>=t){
return this._data.values[i];
}
}
}
return 0;
},


addListener:function(listener){
this._eventSource.addListener(listener);
},


removeListener:function(listener){
this._eventSource.removeListener(listener);
},


replaceListener:function(oldListener,newListener){
this.removeListener(oldListener);
this.addListener(newListener);
}

}




Timeplot.ColumnSource=function(eventSource,column){
Timeplot.DataSource.apply(this,arguments);
this._column=column-1;
};

Object.extend(Timeplot.ColumnSource.prototype,Timeplot.DataSource.prototype);

Timeplot.ColumnSource.prototype.dispose=function(){
this.removeListener(this._processingListener);
this._clear();
}

Timeplot.ColumnSource.prototype._process=function(){
var count=this._eventSource.getCount();
var times=new Array(count);
var values=new Array(count);
var min=Number.MAX_VALUE;
var max=Number.MIN_VALUE;
var i=0;

var iterator=this._eventSource.getAllEventIterator();
while(iterator.hasNext()){
var event=iterator.next();
var time=event.getTime();
times[i]=time;
var value=this._getValue(event);
if(!isNaN(value)){
if(value<min){
min=value;
}
if(value>max){
max=value;
}
values[i]=value;
}
i++;
}

this._data={
times:times,
values:values
};

if(max==Number.MIN_VALUE)max=1;

this._range={
earliestDate:this._eventSource.getEarliestDate(),
latestDate:this._eventSource.getLatestDate(),
min:min,
max:max
};
}

Timeplot.ColumnSource.prototype._getValue=function(event){
return parseFloat(event.getValues()[this._column]);
}




Timeplot.ColumnDiffSource=function(eventSource,column1,column2){
Timeplot.ColumnSource.apply(this,arguments);
this._column2=column2-1;
};

Object.extend(Timeplot.ColumnDiffSource.prototype,Timeplot.ColumnSource.prototype);

Timeplot.ColumnDiffSource.prototype._getValue=function(event){
var a=parseFloat(event.getValues()[this._column]);
var b=parseFloat(event.getValues()[this._column2]);
return a-b;
}


/* geometry.js */




Timeplot.DefaultValueGeometry=function(params){
if(!params)params={};
this._id=("id"in params)?params.id:"g"+Math.round(Math.random()*1000000);
this._axisColor=("axisColor"in params)?((typeof params.axisColor=="string")?new Timeplot.Color(params.axisColor):params.axisColor):new Timeplot.Color("#606060"),
this._gridColor=("gridColor"in params)?((typeof params.gridColor=="string")?new Timeplot.Color(params.gridColor):params.gridColor):null,
this._gridLineWidth=("gridLineWidth"in params)?params.gridLineWidth:0.5;
this._axisLabelsPlacement=("axisLabelsPlacement"in params)?params.axisLabelsPlacement:"right";
this._gridSpacing=("gridSpacing"in params)?params.gridStep:50;
this._gridType=("gridType"in params)?params.gridType:"short";
this._gridShortSize=("gridShortSize"in params)?params.gridShortSize:10;
this._minValue=("min"in params)?params.min:null;
this._maxValue=("max"in params)?params.max:null;
this._linMap={
direct:function(v){
return v;
},
inverse:function(y){
return y;
}
}
this._map=this._linMap;
this._labels=[];
this._grid=[];
}

Timeplot.DefaultValueGeometry.prototype={


setTimeplot:function(timeplot){
this._timeplot=timeplot;
this._canvas=timeplot.getCanvas();
this.reset();
},


setRange:function(range){
if((this._minValue==null)||((this._minValue!=null)&&(range.min<this._minValue))){
this._minValue=range.min;
}
if((this._maxValue==null)||((this._maxValue!=null)&&(range.max*1.05>this._maxValue))){
this._maxValue=range.max*1.05;
}

this._updateMappedValues();

if(!(this._minValue==0&&this._maxValue==0)){
this._grid=this._calculateGrid();
}
},


reset:function(){
this._clearLabels();
this._updateMappedValues();
this._grid=this._calculateGrid();
},


toScreen:function(value){
if(this._canvas&&this._maxValue){
var v=value-this._minValue;
return this._canvas.height*(this._map.direct(v))/this._mappedRange;
}else{
return-50;
}
},


fromScreen:function(y){
if(this._canvas){
return this._map.inverse(this._mappedRange*y/this._canvas.height)+this._minValue;
}else{
return 0;
}
},


paint:function(){
if(this._timeplot){
var ctx=this._canvas.getContext('2d');

ctx.lineJoin='miter';


if(this._gridColor){
var gridGradient=ctx.createLinearGradient(0,0,0,this._canvas.height);
gridGradient.addColorStop(0,this._gridColor.toHexString());
gridGradient.addColorStop(0.3,this._gridColor.toHexString());
gridGradient.addColorStop(1,"rgba(255,255,255,0.5)");

ctx.lineWidth=this._gridLineWidth;
ctx.strokeStyle=gridGradient;

for(var i=0;i<this._grid.length;i++){
var tick=this._grid[i];
var y=Math.floor(tick.y)+0.5;
if(typeof tick.label!="undefined"){
if(this._axisLabelsPlacement=="left"){
var div=this._timeplot.putText(this._id+"-"+i,tick.label,"timeplot-grid-label",{
left:4,
bottom:y+2,
color:this._gridColor.toHexString(),
visibility:"hidden"
});
}else if(this._axisLabelsPlacement=="right"){
var div=this._timeplot.putText(this._id+"-"+i,tick.label,"timeplot-grid-label",{
right:4,
bottom:y+2,
color:this._gridColor.toHexString(),
visibility:"hidden"
});
}
if(y+div.clientHeight<this._canvas.height+10){
div.style.visibility="visible";
}
}


ctx.beginPath();
if(this._gridType=="long"||tick.label==0){
ctx.moveTo(0,y);
ctx.lineTo(this._canvas.width,y);
}else if(this._gridType=="short"){
if(this._axisLabelsPlacement=="left"){
ctx.moveTo(0,y);
ctx.lineTo(this._gridShortSize,y);
}else if(this._axisLabelsPlacement=="right"){
ctx.moveTo(this._canvas.width,y);
ctx.lineTo(this._canvas.width-this._gridShortSize,y);
}
}
ctx.stroke();
}
}


var axisGradient=ctx.createLinearGradient(0,0,0,this._canvas.height);
axisGradient.addColorStop(0,this._axisColor.toString());
axisGradient.addColorStop(0.5,this._axisColor.toString());
axisGradient.addColorStop(1,"rgba(255,255,255,0.5)");

ctx.lineWidth=1;
ctx.strokeStyle=axisGradient;


ctx.beginPath();
ctx.moveTo(0,this._canvas.height);
ctx.lineTo(0,0);
ctx.stroke();


ctx.beginPath();
ctx.moveTo(this._canvas.width,0);
ctx.lineTo(this._canvas.width,this._canvas.height);
ctx.stroke();
}
},


_clearLabels:function(){
for(var i=0;i<this._labels.length;i++){
var l=this._labels[i];
var parent=l.parentNode;
if(parent)parent.removeChild(l);
}
},


_calculateGrid:function(){
var grid=[];

if(!this._canvas||this._valueRange==0)return grid;

var power=0;
if(this._valueRange>1){
while(Math.pow(10,power)<this._valueRange){
power++;
}
power--;
}else{
while(Math.pow(10,power)>this._valueRange){
power--;
}
}

var unit=Math.pow(10,power);
var inc=unit;
while(true){
var dy=this.toScreen(this._minValue+inc);

while(dy<this._gridSpacing){
inc+=unit;
dy=this.toScreen(this._minValue+inc);
}

if(dy>2*this._gridSpacing){
unit/=10;
inc=unit;
}else{
break;
}
}

var v=0;
var y=this.toScreen(v);
if(this._minValue>=0){
while(y<this._canvas.height){
if(y>0){
grid.push({y:y,label:v});
}
v+=inc;
y=this.toScreen(v);
}
}else if(this._maxValue<=0){
while(y>0){
if(y<this._canvas.height){
grid.push({y:y,label:v});
}
v-=inc;
y=this.toScreen(v);
}
}else{
while(y<this._canvas.height){
if(y>0){
grid.push({y:y,label:v});
}
v+=inc;
y=this.toScreen(v);
}
v=-inc;
y=this.toScreen(v);
while(y>0){
if(y<this._canvas.height){
grid.push({y:y,label:v});
}
v-=inc;
y=this.toScreen(v);
}
}

return grid;
},


_updateMappedValues:function(){
this._valueRange=Math.abs(this._maxValue-this._minValue);
this._mappedRange=this._map.direct(this._valueRange);
}

}




Timeplot.LogarithmicValueGeometry=function(params){
Timeplot.DefaultValueGeometry.apply(this,arguments);
this._logMap={
direct:function(v){
return Math.log(v+1)/Math.log(10);
},
inverse:function(y){
return Math.exp(Math.log(10)*y)-1;
}
}
this._mode="log";
this._map=this._logMap;
this._calculateGrid=this._logarithmicCalculateGrid;
};

Timeplot.LogarithmicValueGeometry.prototype._linearCalculateGrid=Timeplot.DefaultValueGeometry.prototype._calculateGrid;

Object.extend(Timeplot.LogarithmicValueGeometry.prototype,Timeplot.DefaultValueGeometry.prototype);


Timeplot.LogarithmicValueGeometry.prototype._logarithmicCalculateGrid=function(){
var grid=[];

if(!this._canvas||this._valueRange==0)return grid;

var v=1;
var y=this.toScreen(v);
while(y<this._canvas.height||isNaN(y)){
if(y>0){
grid.push({y:y,label:v});
}
v*=10;
y=this.toScreen(v);
}

return grid;
};


Timeplot.LogarithmicValueGeometry.prototype.actLinear=function(){
this._mode="lin";
this._map=this._linMap;
this._calculateGrid=this._linearCalculateGrid;
this.reset();
}


Timeplot.LogarithmicValueGeometry.prototype.actLogarithmic=function(){
this._mode="log";
this._map=this._logMap;
this._calculateGrid=this._logarithmicCalculateGrid;
this.reset();
}


Timeplot.LogarithmicValueGeometry.prototype.toggle=function(){
if(this._mode=="log"){
this.actLinear();
}else{
this.actLogarithmic();
}
}




Timeplot.DefaultTimeGeometry=function(params){
if(!params)params={};
this._id=("id"in params)?params.id:"g"+Math.round(Math.random()*1000000);
this._locale=("locale"in params)?params.locale:"en";
this._timeZone=("timeZone"in params)?params.timeZone:SimileAjax.DateTime.getTimezone();
this._labeller=("labeller"in params)?params.labeller:null;
this._axisColor=("axisColor"in params)?((params.axisColor=="string")?new Timeplot.Color(params.axisColor):params.axisColor):new Timeplot.Color("#606060"),
this._gridColor=("gridColor"in params)?((params.gridColor=="string")?new Timeplot.Color(params.gridColor):params.gridColor):null,
this._gridLineWidth=("gridLineWidth"in params)?params.gridLineWidth:0.5;
this._axisLabelsPlacement=("axisLabelsPlacement"in params)?params.axisLabelsPlacement:"bottom";
this._gridStep=("gridStep"in params)?params.gridStep:100;
this._gridStepRange=("gridStepRange"in params)?params.gridStepRange:20;
this._min=("min"in params)?params.min:null;
this._max=("max"in params)?params.max:null;
this._timeValuePosition=("timeValuePosition"in params)?params.timeValuePosition:"bottom";
this._unit=("unit"in params)?params.unit:Timeline.NativeDateUnit;
this._linMap={
direct:function(t){
return t;
},
inverse:function(x){
return x;
}
}
this._map=this._linMap;
this._labeler=this._unit.createLabeller(this._locale,this._timeZone);
var dateParser=this._unit.getParser("iso8601");
if(this._min&&!this._min.getTime){
this._min=dateParser(this._min);
}
if(this._max&&!this._max.getTime){
this._max=dateParser(this._max);
}
this._grid=[];
}

Timeplot.DefaultTimeGeometry.prototype={


setTimeplot:function(timeplot){
this._timeplot=timeplot;
this._canvas=timeplot.getCanvas();
this.reset();
},


setRange:function(range){
if(this._min){
this._earliestDate=this._min;
}else if(range.earliestDate&&((this._earliestDate==null)||((this._earliestDate!=null)&&(range.earliestDate.getTime()<this._earliestDate.getTime())))){
this._earliestDate=range.earliestDate;
}

if(this._max){
this._latestDate=this._max;
}else if(range.latestDate&&((this._latestDate==null)||((this._latestDate!=null)&&(range.latestDate.getTime()>this._latestDate.getTime())))){
this._latestDate=range.latestDate;
}

if(!this._earliestDate&&!this._latestDate){
this._grid=[];
}else{
this.reset();
}
},


reset:function(){
this._updateMappedValues();
if(this._canvas)this._grid=this._calculateGrid();
},


toScreen:function(time){
if(this._canvas&&this._latestDate){
var t=time-this._earliestDate.getTime();
return this._canvas.width*this._map.direct(t)/this._mappedPeriod;
}else{
return-50;
}
},


fromScreen:function(x){
if(this._canvas){
return this._map.inverse(this._mappedPeriod*x/this._canvas.width)+this._earliestDate.getTime();
}else{
return 0;
}
},


getPeriod:function(){
return this._period;
},


getLabeler:function(){
return this._labeler;
},


getUnit:function(){
return this._unit;
},


paint:function(){
if(this._canvas){
var unit=this._unit;
var ctx=this._canvas.getContext('2d');

var gradient=ctx.createLinearGradient(0,0,0,this._canvas.height);

ctx.strokeStyle=gradient;
ctx.lineWidth=this._gridLineWidth;
ctx.lineJoin='miter';


if(this._gridColor){
gradient.addColorStop(0,this._gridColor.toString());
gradient.addColorStop(1,"rgba(255,255,255,0.9)");

for(var i=0;i<this._grid.length;i++){
var tick=this._grid[i];
var x=Math.floor(tick.x)+0.5;
if(this._axisLabelsPlacement=="top"){
var div=this._timeplot.putText(this._id+"-"+i,tick.label,"timeplot-grid-label",{
left:x+4,
top:2,
visibility:"hidden"
});
}else if(this._axisLabelsPlacement=="bottom"){
var div=this._timeplot.putText(this._id+"-"+i,tick.label,"timeplot-grid-label",{
left:x+4,
bottom:2,
visibility:"hidden"
});
}
if(x+div.clientWidth<this._canvas.width+10){
div.style.visibility="visible";
}


ctx.beginPath();
ctx.moveTo(x,0);
ctx.lineTo(x,this._canvas.height);
ctx.stroke();
}
}


gradient.addColorStop(0,this._axisColor.toString());
gradient.addColorStop(1,"rgba(255,255,255,0.5)");

ctx.lineWidth=1;
gradient.addColorStop(0,this._axisColor.toString());

ctx.beginPath();
ctx.moveTo(0,0);
ctx.lineTo(this._canvas.width,0);
ctx.stroke();
}
},


_calculateGrid:function(){
var grid=[];

var time=SimileAjax.DateTime;
var u=this._unit;
var p=this._period;

if(p==0)return grid;


if(p>time.gregorianUnitLengths[time.MILLENNIUM]){
unit=time.MILLENNIUM;
}else{
for(var unit=time.MILLENNIUM;unit>0;unit--){
if(time.gregorianUnitLengths[unit-1]<=p&&p<time.gregorianUnitLengths[unit]){
unit--;
break;
}
}
}

var t=u.cloneValue(this._earliestDate);

do{
time.roundDownToInterval(t,unit,this._timeZone,1,0);
var x=this.toScreen(u.toNumber(t));
switch(unit){
case time.SECOND:
var l=t.toLocaleTimeString();
break;
case time.MINUTE:
var m=t.getMinutes();
var l=t.getHours()+":"+((m<10)?"0":"")+m;
break;
case time.HOUR:
var l=t.getHours()+":00";
break;
case time.DAY:
case time.WEEK:
case time.MONTH:
var l=t.toLocaleDateString();
break;
case time.YEAR:
case time.DECADE:
case time.CENTURY:
case time.MILLENNIUM:
var l=t.getUTCFullYear();
break;
}
if(x>0){
grid.push({x:x,label:l});
}
time.incrementByInterval(t,unit,this._timeZone);
}while(t.getTime()<this._latestDate.getTime());

return grid;
},


_updateMappedValues:function(){
if(this._latestDate&&this._earliestDate){
this._period=this._latestDate.getTime()-this._earliestDate.getTime();
this._mappedPeriod=this._map.direct(this._period);
}else{
this._period=0;
this._mappedPeriod=0;
}
}

}




Timeplot.MagnifyingTimeGeometry=function(params){
Timeplot.DefaultTimeGeometry.apply(this,arguments);

var g=this;
this._MagnifyingMap={
direct:function(t){
if(t<g._leftTimeMargin){
var x=t*g._leftRate;
}else if(g._leftTimeMargin<t&&t<g._rightTimeMargin){
var x=t*g._expandedRate+g._expandedTimeTranslation;
}else{
var x=t*g._rightRate+g._rightTimeTranslation;
}
return x;
},
inverse:function(x){
if(x<g._leftScreenMargin){
var t=x/g._leftRate;
}else if(g._leftScreenMargin<x&&x<g._rightScreenMargin){
var t=x/g._expandedRate+g._expandedScreenTranslation;
}else{
var t=x/g._rightRate+g._rightScreenTranslation;
}
return t;
}
}

this._mode="lin";
this._map=this._linMap;
};

Object.extend(Timeplot.MagnifyingTimeGeometry.prototype,Timeplot.DefaultTimeGeometry.prototype);


Timeplot.MagnifyingTimeGeometry.prototype.initialize=function(timeplot){
Timeplot.DefaultTimeGeometry.prototype.initialize.apply(this,arguments);

if(!this._lens){
this._lens=this._timeplot.putDiv("lens","timeplot-lens");
}

var period=1000*60*60*24*30;

var geometry=this;

var magnifyWith=function(lens){
var aperture=lens.clientWidth;
var loc=geometry._timeplot.locate(lens);
geometry.setMagnifyingParams(loc.x+aperture/2,aperture,period);
geometry.actMagnifying();
geometry._timeplot.paint();
}

var canvasMouseDown=function(elmt,evt,target){
geometry._canvas.startCoords=SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
geometry._canvas.pressed=true;
}

var canvasMouseUp=function(elmt,evt,target){
geometry._canvas.pressed=false;
var coords=SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
if(Timeplot.Math.isClose(coords,geometry._canvas.startCoords,5)){
geometry._lens.style.display="none";
geometry.actLinear();
geometry._timeplot.paint();
}else{
geometry._lens.style.cursor="move";
magnifyWith(geometry._lens);
}
}

var canvasMouseMove=function(elmt,evt,target){
if(geometry._canvas.pressed){
var coords=SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
if(coords.x<0)coords.x=0;
if(coords.x>geometry._canvas.width)coords.x=geometry._canvas.width;
geometry._timeplot.placeDiv(geometry._lens,{
left:geometry._canvas.startCoords.x,
width:coords.x-geometry._canvas.startCoords.x,
bottom:0,
height:geometry._canvas.height,
display:"block"
});
}
}

var lensMouseDown=function(elmt,evt,target){
geometry._lens.startCoords=SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);;
geometry._lens.pressed=true;
}

var lensMouseUp=function(elmt,evt,target){
geometry._lens.pressed=false;
}

var lensMouseMove=function(elmt,evt,target){
if(geometry._lens.pressed){
var coords=SimileAjax.DOM.getEventRelativeCoordinates(evt,elmt);
var lens=geometry._lens;
var left=lens.offsetLeft+coords.x-lens.startCoords.x;
if(left<geometry._timeplot._paddingX)left=geometry._timeplot._paddingX;
if(left+lens.clientWidth>geometry._canvas.width-geometry._timeplot._paddingX)left=geometry._canvas.width-lens.clientWidth+geometry._timeplot._paddingX;
lens.style.left=left;
magnifyWith(lens);
}
}

if(!this._canvas.instrumented){
SimileAjax.DOM.registerEvent(this._canvas,"mousedown",canvasMouseDown);
SimileAjax.DOM.registerEvent(this._canvas,"mousemove",canvasMouseMove);
SimileAjax.DOM.registerEvent(this._canvas,"mouseup",canvasMouseUp);
SimileAjax.DOM.registerEvent(this._canvas,"mouseup",lensMouseUp);
this._canvas.instrumented=true;
}

if(!this._lens.instrumented){
SimileAjax.DOM.registerEvent(this._lens,"mousedown",lensMouseDown);
SimileAjax.DOM.registerEvent(this._lens,"mousemove",lensMouseMove);
SimileAjax.DOM.registerEvent(this._lens,"mouseup",lensMouseUp);
SimileAjax.DOM.registerEvent(this._lens,"mouseup",canvasMouseUp);
this._lens.instrumented=true;
}
}


Timeplot.MagnifyingTimeGeometry.prototype.setMagnifyingParams=function(c,a,b){
a=a/2;
b=b/2;

var w=this._canvas.width;
var d=this._period;

if(c<0)c=0;
if(c>w)c=w;

if(c-a<0)a=c;
if(c+a>w)a=w-c;

var ct=this.fromScreen(c)-this._earliestDate.getTime();
if(ct-b<0)b=ct;
if(ct+b>d)b=d-ct;

this._centerX=c;
this._centerTime=ct;
this._aperture=a;
this._aperturePeriod=b;

this._leftScreenMargin=this._centerX-this._aperture;
this._rightScreenMargin=this._centerX+this._aperture;
this._leftTimeMargin=this._centerTime-this._aperturePeriod;
this._rightTimeMargin=this._centerTime+this._aperturePeriod;

this._leftRate=(c-a)/(ct-b);
this._expandedRate=a/b;
this._rightRate=(w-c-a)/(d-ct-b);

this._expandedTimeTranslation=this._centerX-this._centerTime*this._expandedRate;
this._expandedScreenTranslation=this._centerTime-this._centerX/this._expandedRate;
this._rightTimeTranslation=(c+a)-(ct+b)*this._rightRate;
this._rightScreenTranslation=(ct+b)-(c+a)/this._rightRate;

this._updateMappedValues();
}


Timeplot.MagnifyingTimeGeometry.prototype.actLinear=function(){
this._mode="lin";
this._map=this._linMap;
this.reset();
}


Timeplot.MagnifyingTimeGeometry.prototype.actMagnifying=function(){
this._mode="Magnifying";
this._map=this._MagnifyingMap;
this.reset();
}


Timeplot.MagnifyingTimeGeometry.prototype.toggle=function(){
if(this._mode=="Magnifying"){
this.actLinear();
}else{
this.actMagnifying();
}
}



/* color.js */






Timeplot.Color=function(color){
this._fromHex(color);
};

Timeplot.Color.prototype={


set:function(r,g,b,a){
this.r=r;
this.g=g;
this.b=b;
this.a=(a)?a:1.0;
return this.check();
},


transparency:function(a){
this.a=a;
return this.check();
},


lighten:function(level){
var color=new Timeplot.Color();
return color.set(
this.r+=parseInt(level,10),
this.g+=parseInt(level,10),
this.b+=parseInt(level,10)
);
},


darken:function(level){
var color=new Timeplot.Color();
return color.set(
this.r-=parseInt(level,10),
this.g-=parseInt(level,10),
this.b-=parseInt(level,10)
);
},


check:function(){
if(this.r>255){
this.r=255;
}else if(this.r<0){
this.r=0;
}
if(this.g>255){
this.g=255;
}else if(this.g<0){
this.g=0;
}
if(this.b>255){
this.b=255;
}else if(this.b<0){
this.b=0;
}
if(this.a>1.0){
this.a=1.0;
}else if(this.a<0.0){
this.a=0.0;
}
return this;
},


toString:function(alpha){
var a=(alpha)?alpha:((this.a)?this.a:1.0);
return'rgba('+this.r+','+this.g+','+this.b+','+a+')';
},


toHexString:function(){
return"#"+this._toHex(this.r)+this._toHex(this.g)+this._toHex(this.b);
},


_fromHex:function(color){
if(/^#?([\da-f]{3}|[\da-f]{6})$/i.test(color)){
color=color.replace(/^#/,'').replace(/^([\da-f])([\da-f])([\da-f])$/i,"$1$1$2$2$3$3");
this.r=parseInt(color.substr(0,2),16);
this.g=parseInt(color.substr(2,2),16);
this.b=parseInt(color.substr(4,2),16);
}else if(/^rgb *\( *\d{0,3} *, *\d{0,3} *, *\d{0,3} *\)$/i.test(color)){
color=color.match(/^rgb *\( *(\d{0,3}) *, *(\d{0,3}) *, *(\d{0,3}) *\)$/i);
this.r=parseInt(color[1],10);
this.g=parseInt(color[2],10);
this.b=parseInt(color[3],10);
}
this.a=1.0;
return this.check();
},


_toHex:function(dec){
var hex="0123456789ABCDEF"
if(dec<0)return"00";
if(dec>255)return"FF";
var i=Math.floor(dec/16);
var j=dec%16;
return hex.charAt(i)+hex.charAt(j);
}

};

/* math.js */



Timeplot.Math={


range:function(f){
var F=f.length;
var min=Number.MAX_VALUE;
var max=Number.MIN_VALUE;

for(var t=0;t<F;t++){
var value=f[t];
if(value<min){
min=value;
}
if(value>max){
max=value;
}
}

return{
min:min,
max:max
}
},


movingAverage:function(f,size){
var F=f.length;
var g=new Array(F);
for(var n=0;n<F;n++){
var value=0;
for(var m=n-size;m<n+size;m++){
if(m<0){
var v=f[0];
}else if(m>=F){
var v=g[n-1];
}else{
var v=f[m];
}
value+=v;
}
g[n]=value/(2*size);
}
return g;
},


integral:function(f){
var F=f.length;

var g=new Array(F);
var sum=0;

for(var t=0;t<F;t++){
sum+=f[t];
g[t]=sum;
}

return g;
},


normalize:function(f){
var F=f.length;
var sum=0.0;

for(var t=0;t<F;t++){
sum+=f[t];
}

for(var t=0;t<F;t++){
f[t]/=sum;
}

return f;
},


convolution:function(f,g){
var F=f.length;
var G=g.length;

var c=new Array(F);

for(var m=0;m<F;m++){
var r=0;
var end=(m+G<F)?m+G:F;
for(var n=m;n<end;n++){
var a=f[n-G];
var b=g[n-m];
r+=a*b;
}
c[m]=r;
}

return c;
},







heavyside:function(size){
var f=new Array(size);
var value=1/size;
for(var t=0;t<size;t++){
f[t]=value;
}
return f;
},


gaussian:function(size,threshold){
with(Math){
var radius=size/2;
var variance=radius*radius/log(threshold);
var g=new Array(size);
for(var t=0;t<size;t++){
var l=t-radius;
g[t]=exp(-variance*l*l);
}
}

return this.normalize(g);
},




round:function(x,n){
with(Math){
if(abs(x)>1){
var l=floor(log(x)/log(10));
var d=round(exp((l-n+1)*log(10)));
var y=round(round(x/d)*d);
return y;
}else{
log("FIXME(SM): still to implement for 0 < abs(x) < 1");
return x;
}
}
},


tanh:function(x){
if(x>5){
return 1;
}else if(x<5){
return-1;
}else{
var expx2=Math.exp(2*x);
return(expx2-1)/(expx2+1);
}
},


isClose:function(a,b,value){
return(a&&b&&Math.abs(a.x-b.x)<value&&Math.abs(a.y-b.y)<value);
}

}

/* processor.js */





Timeplot.Operator={


sum:function(data,params){
return Timeplot.Math.integral(data.values);
},


average:function(data,params){
var size=("size"in params)?params.size:30;
var result=Timeplot.Math.movingAverage(data.values,size);
return result;
}
}




Timeplot.Processor=function(dataSource,operator,params){
this._dataSource=dataSource;
this._operator=operator;
this._params=params;

this._data={
times:new Array(),
values:new Array()
};

this._range={
earliestDate:null,
latestDate:null,
min:0,
max:0
};

var processor=this;
this._processingListener={
onAddMany:function(){processor._process();},
onClear:function(){processor._clear();}
}
this.addListener(this._processingListener);
};

Timeplot.Processor.prototype={

_clear:function(){
this.removeListener(this._processingListener);
this._dataSource._clear();
},

_process:function(){




var data=this._dataSource.getData();
var range=this._dataSource.getRange();

var newValues=this._operator(data,this._params);
var newValueRange=Timeplot.Math.range(newValues);

this._data={
times:data.times,
values:newValues
};

this._range={
earliestDate:range.earliestDate,
latestDate:range.latestDate,
min:newValueRange.min,
max:newValueRange.max
};
},

getRange:function(){
return this._range;
},

getData:function(){
return this._data;
},

getValue:Timeplot.DataSource.prototype.getValue,

addListener:function(listener){
this._dataSource.addListener(listener);
},

removeListener:function(listener){
this._dataSource.removeListener(listener);
}
}
