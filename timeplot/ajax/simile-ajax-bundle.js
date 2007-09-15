

/* platform.js */



SimileAjax.Platform.os={
isMac:false,
isWin:false,
isWin32:false,
isUnix:false
};
SimileAjax.Platform.browser={
isIE:false,
isNetscape:false,
isMozilla:false,
isFirefox:false,
isOpera:false,
isSafari:false,

majorVersion:0,
minorVersion:0
};

(function(){
var an=navigator.appName.toLowerCase();
var ua=navigator.userAgent.toLowerCase();


SimileAjax.Platform.os.isMac=(ua.indexOf('mac')!=-1);
SimileAjax.Platform.os.isWin=(ua.indexOf('win')!=-1);
SimileAjax.Platform.os.isWin32=SimileAjax.Platform.isWin&&(
ua.indexOf('95')!=-1||
ua.indexOf('98')!=-1||
ua.indexOf('nt')!=-1||
ua.indexOf('win32')!=-1||
ua.indexOf('32bit')!=-1
);
SimileAjax.Platform.os.isUnix=(ua.indexOf('x11')!=-1);


SimileAjax.Platform.browser.isIE=(an.indexOf("microsoft")!=-1);
SimileAjax.Platform.browser.isNetscape=(an.indexOf("netscape")!=-1);
SimileAjax.Platform.browser.isMozilla=(ua.indexOf("mozilla")!=-1);
SimileAjax.Platform.browser.isFirefox=(ua.indexOf("firefox")!=-1);
SimileAjax.Platform.browser.isOpera=(an.indexOf("opera")!=-1);
SimileAjax.Platform.browser.isSafari=(an.indexOf("safari")!=-1);

var parseVersionString=function(s){
var a=s.split(".");
SimileAjax.Platform.browser.majorVersion=parseInt(a[0]);
SimileAjax.Platform.browser.minorVersion=parseInt(a[1]);
};
var indexOf=function(s,sub,start){
var i=s.indexOf(sub,start);
return i>=0?i:s.length;
};

if(SimileAjax.Platform.browser.isMozilla){
var offset=ua.indexOf("mozilla/");
if(offset>=0){
parseVersionString(ua.substring(offset+8,indexOf(ua," ",offset)));
}
}
if(SimileAjax.Platform.browser.isIE){
var offset=ua.indexOf("msie ");
if(offset>=0){
parseVersionString(ua.substring(offset+5,indexOf(ua,";",offset)));
}
}
if(SimileAjax.Platform.browser.isNetscape){
var offset=ua.indexOf("rv:");
if(offset>=0){
parseVersionString(ua.substring(offset+3,indexOf(ua,")",offset)));
}
}
if(SimileAjax.Platform.browser.isFirefox){
var offset=ua.indexOf("firefox/");
if(offset>=0){
parseVersionString(ua.substring(offset+8,indexOf(ua," ",offset)));
}
}

if(!("localeCompare"in String.prototype)){
String.prototype.localeCompare=function(s){
if(this<s)return-1;
else if(this>s)return 1;
else return 0;
};
}
})();

SimileAjax.Platform.getDefaultLocale=function(){
return SimileAjax.Platform.clientLocale;
};

/* ajax.js */



SimileAjax.ListenerQueue=function(wildcardHandlerName){
this._listeners=[];
this._wildcardHandlerName=wildcardHandlerName;
};

SimileAjax.ListenerQueue.prototype.add=function(listener){
this._listeners.push(listener);
};

SimileAjax.ListenerQueue.prototype.remove=function(listener){
var listeners=this._listeners;
for(var i=0;i<listeners.length;i++){
if(listeners[i]==listener){
listeners.splice(i,1);
break;
}
}
};

SimileAjax.ListenerQueue.prototype.fire=function(handlerName,args){
var listeners=[].concat(this._listeners);
for(var i=0;i<listeners.length;i++){
var listener=listeners[i];
if(handlerName in listener){
try{
listener[handlerName].apply(listener,args);
}catch(e){
SimileAjax.Debug.exception("Error firing event of name "+handlerName,e);
}
}else if(this._wildcardHandlerName!=null&&
this._wildcardHandlerName in listener){
try{
listener[this._wildcardHandlerName].apply(listener,[handlerName]);
}catch(e){
SimileAjax.Debug.exception("Error firing event of name "+handlerName+" to wildcard handler",e);
}
}
}
};



/* data-structure.js */


SimileAjax.Set=function(a){
this._hash={};
this._count=0;

if(a instanceof Array){
for(var i=0;i<a.length;i++){
this.add(a[i]);
}
}else if(a instanceof SimileAjax.Set){
this.addSet(a);
}
}


SimileAjax.Set.prototype.add=function(o){
if(!(o in this._hash)){
this._hash[o]=true;
this._count++;
return true;
}
return false;
}


SimileAjax.Set.prototype.addSet=function(set){
for(o in set._hash){
this.add(o);
}
}


SimileAjax.Set.prototype.remove=function(o){
if(o in this._hash){
delete this._hash[o];
this._count--;
return true;
}
return false;
}


SimileAjax.Set.prototype.removeSet=function(set){
for(o in set._hash){
this.remove(o);
}
}


SimileAjax.Set.prototype.retainSet=function(set){
for(o in this._hash){
if(!set.contains(o)){
delete this._hash[o];
this._count--;
}
}
}


SimileAjax.Set.prototype.contains=function(o){
return(o in this._hash);
}


SimileAjax.Set.prototype.size=function(){
return this._count;
}


SimileAjax.Set.prototype.toArray=function(){
var a=[];
for(o in this._hash){
a.push(o);
}
return a;
}


SimileAjax.Set.prototype.visit=function(f){
for(o in this._hash){
if(f(o)==true){
break;
}
}
}


SimileAjax.SortedArray=function(compare,initialArray){
this._a=(initialArray instanceof Array)?initialArray:[];
this._compare=compare;
};

SimileAjax.SortedArray.prototype.add=function(elmt){
var sa=this;
var index=this.find(function(elmt2){
return sa._compare(elmt2,elmt);
});

if(index<this._a.length){
this._a.splice(index,0,elmt);
}else{
this._a.push(elmt);
}
};

SimileAjax.SortedArray.prototype.remove=function(elmt){
var sa=this;
var index=this.find(function(elmt2){
return sa._compare(elmt2,elmt);
});

while(index<this._a.length&&this._compare(this._a[index],elmt)==0){
if(this._a[index]==elmt){
this._a.splice(index,1);
return true;
}else{
index++;
}
}
return false;
};

SimileAjax.SortedArray.prototype.removeAll=function(){
this._a=[];
};

SimileAjax.SortedArray.prototype.elementAt=function(index){
return this._a[index];
};

SimileAjax.SortedArray.prototype.length=function(){
return this._a.length;
};

SimileAjax.SortedArray.prototype.find=function(compare){
var a=0;
var b=this._a.length;

while(a<b){
var mid=Math.floor((a+b)/2);
var c=compare(this._a[mid]);
if(mid==a){
return c<0?a+1:a;
}else if(c<0){
a=mid;
}else{
b=mid;
}
}
return a;
};

SimileAjax.SortedArray.prototype.getFirst=function(){
return(this._a.length>0)?this._a[0]:null;
};

SimileAjax.SortedArray.prototype.getLast=function(){
return(this._a.length>0)?this._a[this._a.length-1]:null;
};



SimileAjax.EventIndex=function(unit){
var eventIndex=this;

this._unit=(unit!=null)?unit:SimileAjax.NativeDateUnit;
this._events=new SimileAjax.SortedArray(
function(event1,event2){
return eventIndex._unit.compare(event1.getStart(),event2.getStart());
}
);
this._idToEvent={};
this._indexed=true;
};

SimileAjax.EventIndex.prototype.getUnit=function(){
return this._unit;
};

SimileAjax.EventIndex.prototype.getEvent=function(id){
return this._idToEvent[id];
};

SimileAjax.EventIndex.prototype.add=function(evt){
this._events.add(evt);
this._idToEvent[evt.getID()]=evt;
this._indexed=false;
};

SimileAjax.EventIndex.prototype.removeAll=function(){
this._events.removeAll();
this._idToEvent={};
this._indexed=false;
};

SimileAjax.EventIndex.prototype.getCount=function(){
return this._events.length();
};

SimileAjax.EventIndex.prototype.getIterator=function(startDate,endDate){
if(!this._indexed){
this._index();
}
return new SimileAjax.EventIndex._Iterator(this._events,startDate,endDate,this._unit);
};

SimileAjax.EventIndex.prototype.getReverseIterator=function(startDate,endDate){
if(!this._indexed){
this._index();
}
return new SimileAjax.EventIndex._ReverseIterator(this._events,startDate,endDate,this._unit);
};

SimileAjax.EventIndex.prototype.getAllIterator=function(){
return new SimileAjax.EventIndex._AllIterator(this._events);
};

SimileAjax.EventIndex.prototype.getEarliestDate=function(){
var evt=this._events.getFirst();
return(evt==null)?null:evt.getStart();
};

SimileAjax.EventIndex.prototype.getLatestDate=function(){
var evt=this._events.getLast();
if(evt==null){
return null;
}

if(!this._indexed){
this._index();
}

var index=evt._earliestOverlapIndex;
var date=this._events.elementAt(index).getEnd();
for(var i=index+1;i<this._events.length();i++){
date=this._unit.later(date,this._events.elementAt(i).getEnd());
}

return date;
};

SimileAjax.EventIndex.prototype._index=function(){


var l=this._events.length();
for(var i=0;i<l;i++){
var evt=this._events.elementAt(i);
evt._earliestOverlapIndex=i;
}

var toIndex=1;
for(var i=0;i<l;i++){
var evt=this._events.elementAt(i);
var end=evt.getEnd();

toIndex=Math.max(toIndex,i+1);
while(toIndex<l){
var evt2=this._events.elementAt(toIndex);
var start2=evt2.getStart();

if(this._unit.compare(start2,end)<0){
evt2._earliestOverlapIndex=i;
toIndex++;
}else{
break;
}
}
}
this._indexed=true;
};

SimileAjax.EventIndex._Iterator=function(events,startDate,endDate,unit){
this._events=events;
this._startDate=startDate;
this._endDate=endDate;
this._unit=unit;

this._currentIndex=events.find(function(evt){
return unit.compare(evt.getStart(),startDate);
});
if(this._currentIndex-1>=0){
this._currentIndex=this._events.elementAt(this._currentIndex-1)._earliestOverlapIndex;
}
this._currentIndex--;

this._maxIndex=events.find(function(evt){
return unit.compare(evt.getStart(),endDate);
});

this._hasNext=false;
this._next=null;
this._findNext();
};

SimileAjax.EventIndex._Iterator.prototype={
hasNext:function(){return this._hasNext;},
next:function(){
if(this._hasNext){
var next=this._next;
this._findNext();

return next;
}else{
return null;
}
},
_findNext:function(){
var unit=this._unit;
while((++this._currentIndex)<this._maxIndex){
var evt=this._events.elementAt(this._currentIndex);
if(unit.compare(evt.getStart(),this._endDate)<0&&
unit.compare(evt.getEnd(),this._startDate)>0){

this._next=evt;
this._hasNext=true;
return;
}
}
this._next=null;
this._hasNext=false;
}
};

SimileAjax.EventIndex._ReverseIterator=function(events,startDate,endDate,unit){
this._events=events;
this._startDate=startDate;
this._endDate=endDate;
this._unit=unit;

this._minIndex=events.find(function(evt){
return unit.compare(evt.getStart(),startDate);
});
if(this._minIndex-1>=0){
this._minIndex=this._events.elementAt(this._minIndex-1)._earliestOverlapIndex;
}

this._maxIndex=events.find(function(evt){
return unit.compare(evt.getStart(),endDate);
});

this._currentIndex=this._maxIndex;
this._hasNext=false;
this._next=null;
this._findNext();
};

SimileAjax.EventIndex._ReverseIterator.prototype={
hasNext:function(){return this._hasNext;},
next:function(){
if(this._hasNext){
var next=this._next;
this._findNext();

return next;
}else{
return null;
}
},
_findNext:function(){
var unit=this._unit;
while((--this._currentIndex)>=this._minIndex){
var evt=this._events.elementAt(this._currentIndex);
if(unit.compare(evt.getStart(),this._endDate)<0&&
unit.compare(evt.getEnd(),this._startDate)>0){

this._next=evt;
this._hasNext=true;
return;
}
}
this._next=null;
this._hasNext=false;
}
};

SimileAjax.EventIndex._AllIterator=function(events){
this._events=events;
this._index=0;
};

SimileAjax.EventIndex._AllIterator.prototype={
hasNext:function(){
return this._index<this._events.length();
},
next:function(){
return this._index<this._events.length()?
this._events.elementAt(this._index++):null;
}
};

/* date-time.js */



SimileAjax.DateTime=new Object();

SimileAjax.DateTime.MILLISECOND=0;
SimileAjax.DateTime.SECOND=1;
SimileAjax.DateTime.MINUTE=2;
SimileAjax.DateTime.HOUR=3;
SimileAjax.DateTime.DAY=4;
SimileAjax.DateTime.WEEK=5;
SimileAjax.DateTime.MONTH=6;
SimileAjax.DateTime.YEAR=7;
SimileAjax.DateTime.DECADE=8;
SimileAjax.DateTime.CENTURY=9;
SimileAjax.DateTime.MILLENNIUM=10;

SimileAjax.DateTime.EPOCH=-1;
SimileAjax.DateTime.ERA=-2;


SimileAjax.DateTime.gregorianUnitLengths=[];
(function(){
var d=SimileAjax.DateTime;
var a=d.gregorianUnitLengths;

a[d.MILLISECOND]=1;
a[d.SECOND]=1000;
a[d.MINUTE]=a[d.SECOND]*60;
a[d.HOUR]=a[d.MINUTE]*60;
a[d.DAY]=a[d.HOUR]*24;
a[d.WEEK]=a[d.DAY]*7;
a[d.MONTH]=a[d.DAY]*31;
a[d.YEAR]=a[d.DAY]*365;
a[d.DECADE]=a[d.YEAR]*10;
a[d.CENTURY]=a[d.YEAR]*100;
a[d.MILLENNIUM]=a[d.YEAR]*1000;
})();

SimileAjax.DateTime._dateRegexp=new RegExp(
"^(-?)([0-9]{4})("+[
"(-?([0-9]{2})(-?([0-9]{2}))?)",
"(-?([0-9]{3}))",
"(-?W([0-9]{2})(-?([1-7]))?)"
].join("|")+")?$"
);
SimileAjax.DateTime._timezoneRegexp=new RegExp(
"Z|(([-+])([0-9]{2})(:?([0-9]{2}))?)$"
);
SimileAjax.DateTime._timeRegexp=new RegExp(
"^([0-9]{2})(:?([0-9]{2})(:?([0-9]{2})(\.([0-9]+))?)?)?$"
);


SimileAjax.DateTime.setIso8601Date=function(dateObject,string){


var d=string.match(SimileAjax.DateTime._dateRegexp);
if(!d){
throw new Error("Invalid date string: "+string);
}

var sign=(d[1]=="-")?-1:1;
var year=sign*d[2];
var month=d[5];
var date=d[7];
var dayofyear=d[9];
var week=d[11];
var dayofweek=(d[13])?d[13]:1;

dateObject.setUTCFullYear(year);
if(dayofyear){
dateObject.setUTCMonth(0);
dateObject.setUTCDate(Number(dayofyear));
}else if(week){
dateObject.setUTCMonth(0);
dateObject.setUTCDate(1);
var gd=dateObject.getUTCDay();
var day=(gd)?gd:7;
var offset=Number(dayofweek)+(7*Number(week));

if(day<=4){
dateObject.setUTCDate(offset+1-day);
}else{
dateObject.setUTCDate(offset+8-day);
}
}else{
if(month){
dateObject.setUTCDate(1);
dateObject.setUTCMonth(month-1);
}
if(date){
dateObject.setUTCDate(date);
}
}

return dateObject;
};


SimileAjax.DateTime.setIso8601Time=function(dateObject,string){


var d=string.match(SimileAjax.DateTime._timeRegexp);
if(!d){
SimileAjax.Debug.warn("Invalid time string: "+string);
return false;
}
var hours=d[1];
var mins=Number((d[3])?d[3]:0);
var secs=(d[5])?d[5]:0;
var ms=d[7]?(Number("0."+d[7])*1000):0;

dateObject.setUTCHours(hours);
dateObject.setUTCMinutes(mins);
dateObject.setUTCSeconds(secs);
dateObject.setUTCMilliseconds(ms);

return dateObject;
};


SimileAjax.DateTime.timezoneOffset=new Date().getTimezoneOffset();


SimileAjax.DateTime.setIso8601=function(dateObject,string){


var offset=null;
var comps=(string.indexOf("T")==-1)?string.split(" "):string.split("T");

SimileAjax.DateTime.setIso8601Date(dateObject,comps[0]);
if(comps.length==2){

var d=comps[1].match(SimileAjax.DateTime._timezoneRegexp);
if(d){
if(d[0]=='Z'){
offset=0;
}else{
offset=(Number(d[3])*60)+Number(d[5]);
offset*=((d[2]=='-')?1:-1);
}
comps[1]=comps[1].substr(0,comps[1].length-d[0].length);
}

SimileAjax.DateTime.setIso8601Time(dateObject,comps[1]);
}
if(offset==null){
offset=dateObject.getTimezoneOffset();
}
dateObject.setTime(dateObject.getTime()+offset*60000);

return dateObject;
};


SimileAjax.DateTime.parseIso8601DateTime=function(string){
try{
return SimileAjax.DateTime.setIso8601(new Date(0),string);
}catch(e){
return null;
}
};


SimileAjax.DateTime.parseGregorianDateTime=function(o){
if(o==null){
return null;
}else if(o instanceof Date){
return o;
}

var s=o.toString();
if(s.length>0&&s.length<8){
var space=s.indexOf(" ");
if(space>0){
var year=parseInt(s.substr(0,space));
var suffix=s.substr(space+1);
if(suffix.toLowerCase()=="bc"){
year=1-year;
}
}else{
var year=parseInt(s);
}

var d=new Date(0);
d.setUTCFullYear(year);

return d;
}

try{
return new Date(Date.parse(s));
}catch(e){
return null;
}
};


SimileAjax.DateTime.roundDownToInterval=function(date,intervalUnit,timeZone,multiple,firstDayOfWeek){
var timeShift=timeZone*
SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.HOUR];

var date2=new Date(date.getTime()+timeShift);
var clearInDay=function(d){
d.setUTCMilliseconds(0);
d.setUTCSeconds(0);
d.setUTCMinutes(0);
d.setUTCHours(0);
};
var clearInYear=function(d){
clearInDay(d);
d.setUTCDate(1);
d.setUTCMonth(0);
};

switch(intervalUnit){
case SimileAjax.DateTime.MILLISECOND:
var x=date2.getUTCMilliseconds();
date2.setUTCMilliseconds(x-(x%multiple));
break;
case SimileAjax.DateTime.SECOND:
date2.setUTCMilliseconds(0);

var x=date2.getUTCSeconds();
date2.setUTCSeconds(x-(x%multiple));
break;
case SimileAjax.DateTime.MINUTE:
date2.setUTCMilliseconds(0);
date2.setUTCSeconds(0);

var x=date2.getUTCMinutes();
date2.setTime(date2.getTime()-
(x%multiple)*SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.MINUTE]);
break;
case SimileAjax.DateTime.HOUR:
date2.setUTCMilliseconds(0);
date2.setUTCSeconds(0);
date2.setUTCMinutes(0);

var x=date2.getUTCHours();
date2.setUTCHours(x-(x%multiple));
break;
case SimileAjax.DateTime.DAY:
clearInDay(date2);
break;
case SimileAjax.DateTime.WEEK:
clearInDay(date2);
var d=(date2.getUTCDay()+7-firstDayOfWeek)%7;
date2.setTime(date2.getTime()-
d*SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.DAY]);
break;
case SimileAjax.DateTime.MONTH:
clearInDay(date2);
date2.setUTCDate(1);

var x=date2.getUTCMonth();
date2.setUTCMonth(x-(x%multiple));
break;
case SimileAjax.DateTime.YEAR:
clearInYear(date2);

var x=date2.getUTCFullYear();
date2.setUTCFullYear(x-(x%multiple));
break;
case SimileAjax.DateTime.DECADE:
clearInYear(date2);
date2.setUTCFullYear(Math.floor(date2.getUTCFullYear()/10)*10);
break;
case SimileAjax.DateTime.CENTURY:
clearInYear(date2);
date2.setUTCFullYear(Math.floor(date2.getUTCFullYear()/100)*100);
break;
case SimileAjax.DateTime.MILLENNIUM:
clearInYear(date2);
date2.setUTCFullYear(Math.floor(date2.getUTCFullYear()/1000)*1000);
break;
}

date.setTime(date2.getTime()-timeShift);
};


SimileAjax.DateTime.roundUpToInterval=function(date,intervalUnit,timeZone,multiple,firstDayOfWeek){
var originalTime=date.getTime();
SimileAjax.DateTime.roundDownToInterval(date,intervalUnit,timeZone,multiple,firstDayOfWeek);
if(date.getTime()<originalTime){
date.setTime(date.getTime()+
SimileAjax.DateTime.gregorianUnitLengths[intervalUnit]*multiple);
}
};


SimileAjax.DateTime.incrementByInterval=function(date,intervalUnit){
switch(intervalUnit){
case SimileAjax.DateTime.MILLISECOND:
date.setTime(date.getTime()+1)
break;
case SimileAjax.DateTime.SECOND:
date.setTime(date.getTime()+1000);
break;
case SimileAjax.DateTime.MINUTE:
date.setTime(date.getTime()+
SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.MINUTE]);
break;
case SimileAjax.DateTime.HOUR:
date.setTime(date.getTime()+
SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.HOUR]);
break;
case SimileAjax.DateTime.DAY:
date.setUTCDate(date.getUTCDate()+1);
break;
case SimileAjax.DateTime.WEEK:
date.setUTCDate(date.getUTCDate()+7);
break;
case SimileAjax.DateTime.MONTH:
date.setUTCMonth(date.getUTCMonth()+1);
break;
case SimileAjax.DateTime.YEAR:
date.setUTCFullYear(date.getUTCFullYear()+1);
break;
case SimileAjax.DateTime.DECADE:
date.setUTCFullYear(date.getUTCFullYear()+10);
break;
case SimileAjax.DateTime.CENTURY:
date.setUTCFullYear(date.getUTCFullYear()+100);
break;
case SimileAjax.DateTime.MILLENNIUM:
date.setUTCFullYear(date.getUTCFullYear()+1000);
break;
}
};


SimileAjax.DateTime.removeTimeZoneOffset=function(date,timeZone){
return new Date(date.getTime()+
timeZone*SimileAjax.DateTime.gregorianUnitLengths[SimileAjax.DateTime.HOUR]);
};


SimileAjax.DateTime.getTimezone=function(){
var d=new Date();
var utcHours=d.getUTCHours();
var utcDay=d.getUTCDate();
var localHours=d.getHours();
var localDay=d.getDate();
if(utcDay==localDay){
return localHours-utcHours;
}else if(utcHours>12){
return 24-utcHours+localHours;
}else{
return-(utcHours+24-localHours);
}
};

/* debug.js */



SimileAjax.Debug={
silent:false
};

SimileAjax.Debug.log=function(msg){
var f;
if("console"in window&&"log"in window.console){
f=function(msg2){
console.log(msg2);
}
}else{
f=function(msg2){
if(!SimileAjax.Debug.silent){
alert(msg2);
}
}
}
SimileAjax.Debug.log=f;
f(msg);
};

SimileAjax.Debug.warn=function(msg){
var f;
if("console"in window&&"warn"in window.console){
f=function(msg2){
console.warn(msg2);
}
}else{
f=function(msg2){
if(!SimileAjax.Debug.silent){
alert(msg2);
}
}
}
SimileAjax.Debug.warn=f;
f(msg);
};

SimileAjax.Debug.exception=function(e,msg){
var f,params=SimileAjax.parseURLParameters();
if(params.errors=="throw"||SimileAjax.params.errors=="throw"){
f=function(e2,msg2){
throw(e2);
};
}else if("console"in window&&"error"in window.console){
f=function(e2,msg2){
if(msg2!=null){
console.error(msg2+" %o",e2);
}else{
console.error(e2);
}
throw(e2);
};
}else{
f=function(e2,msg2){
if(!SimileAjax.Debug.silent){
alert("Caught exception: "+msg2+"\n\nDetails: "+("description"in e2?e2.description:e2));
}
throw(e2);
};
}
SimileAjax.Debug.exception=f;
f(e,msg);
};

SimileAjax.Debug.objectToString=function(o){
return SimileAjax.Debug._objectToString(o,"");
};

SimileAjax.Debug._objectToString=function(o,indent){
var indent2=indent+" ";
if(typeof o=="object"){
var s="{";
for(n in o){
s+=indent2+n+": "+SimileAjax.Debug._objectToString(o[n],indent2)+"\n";
}
s+=indent+"}";
return s;
}else if(typeof o=="array"){
var s="[";
for(var n=0;n<o.length;n++){
s+=SimileAjax.Debug._objectToString(o[n],indent2)+"\n";
}
s+=indent+"]";
return s;
}else{
return o;
}
};


/* dom.js */



SimileAjax.DOM=new Object();

SimileAjax.DOM.registerEventWithObject=function(elmt,eventName,obj,handlerName){
SimileAjax.DOM.registerEvent(elmt,eventName,function(elmt2,evt,target){
return obj[handlerName].call(obj,elmt2,evt,target);
});
};

SimileAjax.DOM.registerEvent=function(elmt,eventName,handler){
var handler2=function(evt){
evt=(evt)?evt:((event)?event:null);
if(evt){
var target=(evt.target)?
evt.target:((evt.srcElement)?evt.srcElement:null);
if(target){
target=(target.nodeType==1||target.nodeType==9)?
target:target.parentNode;
}

return handler(elmt,evt,target);
}
return true;
}

if(SimileAjax.Platform.browser.isIE){
elmt.attachEvent("on"+eventName,handler2);
}else{
elmt.addEventListener(eventName,handler2,false);
}
};

SimileAjax.DOM.getPageCoordinates=function(elmt){
var left=0;
var top=0;

if(elmt.nodeType!=1){
elmt=elmt.parentNode;
}

var elmt2=elmt;
while(elmt2!=null){
left+=elmt2.offsetLeft;
top+=elmt2.offsetTop;
elmt2=elmt2.offsetParent;
}

var body=document.body;
while(elmt!=null&&elmt!=body){
if("scrollLeft"in elmt){
left-=elmt.scrollLeft;
top-=elmt.scrollTop;
}
elmt=elmt.parentNode;
}

return{left:left,top:top};
};

SimileAjax.DOM.getSize=function(elmt){
var w=this.getStyle(elmt,"width");
var h=this.getStyle(elmt,"height");
if(w.indexOf("px")>-1)w=w.replace("px","");
if(h.indexOf("px")>-1)h=h.replace("px","");
return{
w:w,
h:h
}
}

SimileAjax.DOM.getStyle=function(elmt,styleProp){
if(elmt.currentStyle){
var style=elmt.currentStyle[styleProp];
}else if(window.getComputedStyle){
var style=document.defaultView.getComputedStyle(elmt,null).getPropertyValue(styleProp);
}else{
var style="";
}
return style;
}

SimileAjax.DOM.getEventRelativeCoordinates=function(evt,elmt){
if(SimileAjax.Platform.browser.isIE){
return{
x:evt.offsetX,
y:evt.offsetY
};
}else{
var coords=SimileAjax.DOM.getPageCoordinates(elmt);
return{
x:evt.pageX-coords.left,
y:evt.pageY-coords.top
};
}
};

SimileAjax.DOM.getEventPageCoordinates=function(evt){
if(SimileAjax.Platform.browser.isIE){
return{
x:evt.clientX+document.body.scrollLeft,
y:evt.clientY+document.body.scrollTop
};
}else{
return{
x:evt.pageX,
y:evt.pageY
};
}
};

SimileAjax.DOM.hittest=function(x,y,except){
return SimileAjax.DOM._hittest(document.body,x,y,except);
};

SimileAjax.DOM._hittest=function(elmt,x,y,except){
var childNodes=elmt.childNodes;
outer:for(var i=0;i<childNodes.length;i++){
var childNode=childNodes[i];
for(var j=0;j<except.length;j++){
if(childNode==except[j]){
continue outer;
}
}

if(childNode.offsetWidth==0&&childNode.offsetHeight==0){

var hitNode=SimileAjax.DOM._hittest(childNode,x,y,except);
if(hitNode!=childNode){
return hitNode;
}
}else{
var top=0;
var left=0;

var node=childNode;
while(node){
top+=node.offsetTop;
left+=node.offsetLeft;
node=node.offsetParent;
}

if(left<=x&&top<=y&&(x-left)<childNode.offsetWidth&&(y-top)<childNode.offsetHeight){
return SimileAjax.DOM._hittest(childNode,x,y,except);
}else if(childNode.nodeType==1&&childNode.tagName=="TR"){

var childNode2=SimileAjax.DOM._hittest(childNode,x,y,except);
if(childNode2!=childNode){
return childNode2;
}
}
}
}
return elmt;
};

SimileAjax.DOM.cancelEvent=function(evt){
evt.returnValue=false;
evt.cancelBubble=true;
if("preventDefault"in evt){
evt.preventDefault();
}
};

SimileAjax.DOM.appendClassName=function(elmt,className){
var classes=elmt.className.split(" ");
for(var i=0;i<classes.length;i++){
if(classes[i]==className){
return;
}
}
classes.push(className);
elmt.className=classes.join(" ");
};

SimileAjax.DOM.createInputElement=function(type){
var div=document.createElement("div");
div.innerHTML="<input type='"+type+"' />";

return div.firstChild;
};

SimileAjax.DOM.createDOMFromTemplate=function(template){
var result={};
result.elmt=SimileAjax.DOM._createDOMFromTemplate(template,result,null);

return result;
};

SimileAjax.DOM._createDOMFromTemplate=function(templateNode,result,parentElmt){
if(templateNode==null){

return null;
}else if(typeof templateNode!="object"){
var node=document.createTextNode(templateNode);
if(parentElmt!=null){
parentElmt.appendChild(node);
}
return node;
}else{
var elmt=null;
if("tag"in templateNode){
var tag=templateNode.tag;
if(parentElmt!=null){
if(tag=="tr"){
elmt=parentElmt.insertRow(parentElmt.rows.length);
}else if(tag=="td"){
elmt=parentElmt.insertCell(parentElmt.cells.length);
}
}
if(elmt==null){
elmt=tag=="input"?
SimileAjax.DOM.createInputElement(templateNode.type):
document.createElement(tag);

if(parentElmt!=null){
parentElmt.appendChild(elmt);
}
}
}else{
elmt=templateNode.elmt;
if(parentElmt!=null){
parentElmt.appendChild(elmt);
}
}

for(var attribute in templateNode){
var value=templateNode[attribute];

if(attribute=="field"){
result[value]=elmt;

}else if(attribute=="className"){
elmt.className=value;
}else if(attribute=="id"){
elmt.id=value;
}else if(attribute=="title"){
elmt.title=value;
}else if(attribute=="type"&&elmt.tagName=="input"){

}else if(attribute=="style"){
for(n in value){
var v=value[n];
if(n=="float"){
n=SimileAjax.Platform.browser.isIE?"styleFloat":"cssFloat";
}
elmt.style[n]=v;
}
}else if(attribute=="children"){
for(var i=0;i<value.length;i++){
SimileAjax.DOM._createDOMFromTemplate(value[i],result,elmt);
}
}else if(attribute!="tag"&&attribute!="elmt"){
elmt.setAttribute(attribute,value);
}
}
return elmt;
}
}

SimileAjax.DOM._cachedParent=null;
SimileAjax.DOM.createElementFromString=function(s){
if(SimileAjax.DOM._cachedParent==null){
SimileAjax.DOM._cachedParent=document.createElement("div");
}
SimileAjax.DOM._cachedParent.innerHTML=s;
return SimileAjax.DOM._cachedParent.firstChild;
};

SimileAjax.DOM.createDOMFromString=function(root,s,fieldElmts){
var elmt=typeof root=="string"?document.createElement(root):root;
elmt.innerHTML=s;

var dom={elmt:elmt};
SimileAjax.DOM._processDOMChildrenConstructedFromString(dom,elmt,fieldElmts!=null?fieldElmts:{});

return dom;
};

SimileAjax.DOM._processDOMConstructedFromString=function(dom,elmt,fieldElmts){
var id=elmt.id;
if(id!=null&&id.length>0){
elmt.removeAttribute("id");
if(id in fieldElmts){
var parentElmt=elmt.parentNode;
parentElmt.insertBefore(fieldElmts[id],elmt);
parentElmt.removeChild(elmt);

dom[id]=fieldElmts[id];
return;
}else{
dom[id]=elmt;
}
}

if(elmt.hasChildNodes()){
SimileAjax.DOM._processDOMChildrenConstructedFromString(dom,elmt,fieldElmts);
}
};

SimileAjax.DOM._processDOMChildrenConstructedFromString=function(dom,elmt,fieldElmts){
var node=elmt.firstChild;
while(node!=null){
var node2=node.nextSibling;
if(node.nodeType==1){
SimileAjax.DOM._processDOMConstructedFromString(dom,node,fieldElmts);
}
node=node2;
}
};


/* graphics.js */



SimileAjax.Graphics=new Object();


SimileAjax.Graphics.pngIsTranslucent=(!SimileAjax.Platform.browser.isIE)||(SimileAjax.Platform.browser.majorVersion>6);


SimileAjax.Graphics._createTranslucentImage1=function(url,verticalAlign){
elmt=document.createElement("img");
elmt.setAttribute("src",url);
if(verticalAlign!=null){
elmt.style.verticalAlign=verticalAlign;
}
return elmt;
};
SimileAjax.Graphics._createTranslucentImage2=function(url,verticalAlign){
elmt=document.createElement("img");
elmt.style.width="1px";
elmt.style.height="1px";
elmt.style.filter="progid:DXImageTransform.Microsoft.AlphaImageLoader(src='"+url+"', sizingMethod='image')";
elmt.style.verticalAlign=(verticalAlign!=null)?verticalAlign:"middle";
return elmt;
};


SimileAjax.Graphics.createTranslucentImage=SimileAjax.Graphics.pngIsTranslucent?
SimileAjax.Graphics._createTranslucentImage1:
SimileAjax.Graphics._createTranslucentImage2;

SimileAjax.Graphics._createTranslucentImageHTML1=function(url,verticalAlign){
return"<img src=\""+url+"\""+
(verticalAlign!=null?" style=\"vertical-align: "+verticalAlign+";\"":"")+
" />";
};
SimileAjax.Graphics._createTranslucentImageHTML2=function(url,verticalAlign){
var style=
"width: 1px; height: 1px; "+
"filter:progid:DXImageTransform.Microsoft.AlphaImageLoader(src='"+url+"', sizingMethod='image');"+
(verticalAlign!=null?" vertical-align: "+verticalAlign+";":"");

return"<img src='"+url+"' style=\""+style+"\" />";
};


SimileAjax.Graphics.createTranslucentImageHTML=SimileAjax.Graphics.pngIsTranslucent?
SimileAjax.Graphics._createTranslucentImageHTML1:
SimileAjax.Graphics._createTranslucentImageHTML2;


SimileAjax.Graphics.setOpacity=function(elmt,opacity){
if(SimileAjax.Platform.browser.isIE){
elmt.style.filter="progid:DXImageTransform.Microsoft.Alpha(Style=0,Opacity="+opacity+")";
}else{
var o=(opacity/100).toString();
elmt.style.opacity=o;
elmt.style.MozOpacity=o;
}
};


SimileAjax.Graphics._bubbleMargins={
top:33,
bottom:42,
left:33,
right:40
}


SimileAjax.Graphics._arrowOffsets={
top:0,
bottom:9,
left:1,
right:8
}

SimileAjax.Graphics._bubblePadding=15;
SimileAjax.Graphics._bubblePointOffset=6;
SimileAjax.Graphics._halfArrowWidth=18;


SimileAjax.Graphics.createBubbleForContentAndPoint=function(div,pageX,pageY,contentWidth,orientation){
if(typeof contentWidth!="number"){
contentWidth=300;
}

div.style.position="absolute";
div.style.left="-5000px";
div.style.top="0px";
div.style.width=contentWidth+"px";
document.body.appendChild(div);

window.setTimeout(function(){
var width=div.scrollWidth+10;
var height=div.scrollHeight+10;

var bubble=SimileAjax.Graphics.createBubbleForPoint(pageX,pageY,width,height,orientation);

document.body.removeChild(div);
div.style.position="static";
div.style.left="";
div.style.top="";
div.style.width=width+"px";
bubble.content.appendChild(div);
},200);
};


SimileAjax.Graphics.createBubbleForPoint=function(pageX,pageY,contentWidth,contentHeight,orientation){
function getWindowDims(){
if(typeof window.innerHeight=='number'){
return{w:window.innerWidth,h:window.innerHeight};
}else if(document.documentElement&&document.documentElement.clientHeight){
return{
w:document.documentElement.clientWidth,
h:document.documentElement.clientHeight
};
}else if(document.body&&document.body.clientHeight){
return{
w:document.body.clientWidth,
h:document.body.clientHeight
};
}
}

var close=function(){
if(!bubble._closed){
document.body.removeChild(bubble._div);
bubble._doc=null;
bubble._div=null;
bubble._content=null;
bubble._closed=true;
}
}
var bubble={
_closed:false
};

var dims=getWindowDims();
var docWidth=dims.w;
var docHeight=dims.h;

var margins=SimileAjax.Graphics._bubbleMargins;
contentWidth=parseInt(contentWidth,10);
contentHeight=parseInt(contentHeight,10);
var bubbleWidth=margins.left+contentWidth+margins.right;
var bubbleHeight=margins.top+contentHeight+margins.bottom;

var pngIsTranslucent=SimileAjax.Graphics.pngIsTranslucent;
var urlPrefix=SimileAjax.urlPrefix;

var setImg=function(elmt,url,width,height){
elmt.style.position="absolute";
elmt.style.width=width+"px";
elmt.style.height=height+"px";
if(pngIsTranslucent){
elmt.style.background="url("+url+")";
}else{
elmt.style.filter="progid:DXImageTransform.Microsoft.AlphaImageLoader(src='"+url+"', sizingMethod='crop')";
}
}
var div=document.createElement("div");
div.style.width=bubbleWidth+"px";
div.style.height=bubbleHeight+"px";
div.style.position="absolute";
div.style.zIndex=1000;

var layer=SimileAjax.WindowManager.pushLayer(close,true,div);
bubble._div=div;
bubble.close=function(){SimileAjax.WindowManager.popLayer(layer);}

var divInner=document.createElement("div");
divInner.style.width="100%";
divInner.style.height="100%";
divInner.style.position="relative";
div.appendChild(divInner);

var createImg=function(url,left,top,width,height){
var divImg=document.createElement("div");
divImg.style.left=left+"px";
divImg.style.top=top+"px";
setImg(divImg,url,width,height);
divInner.appendChild(divImg);
}

createImg(urlPrefix+"images/bubble-top-left.png",0,0,margins.left,margins.top);
createImg(urlPrefix+"images/bubble-top.png",margins.left,0,contentWidth,margins.top);
createImg(urlPrefix+"images/bubble-top-right.png",margins.left+contentWidth,0,margins.right,margins.top);

createImg(urlPrefix+"images/bubble-left.png",0,margins.top,margins.left,contentHeight);
createImg(urlPrefix+"images/bubble-right.png",margins.left+contentWidth,margins.top,margins.right,contentHeight);

createImg(urlPrefix+"images/bubble-bottom-left.png",0,margins.top+contentHeight,margins.left,margins.bottom);
createImg(urlPrefix+"images/bubble-bottom.png",margins.left,margins.top+contentHeight,contentWidth,margins.bottom);
createImg(urlPrefix+"images/bubble-bottom-right.png",margins.left+contentWidth,margins.top+contentHeight,margins.right,margins.bottom);

var divClose=document.createElement("div");
divClose.style.left=(bubbleWidth-margins.right+SimileAjax.Graphics._bubblePadding-16-2)+"px";
divClose.style.top=(margins.top-SimileAjax.Graphics._bubblePadding+1)+"px";
divClose.style.cursor="pointer";
setImg(divClose,urlPrefix+"images/close-button.png",16,16);
SimileAjax.WindowManager.registerEventWithObject(divClose,"click",bubble,"close");
divInner.appendChild(divClose);

var divContent=document.createElement("div");
divContent.style.position="absolute";
divContent.style.left=margins.left+"px";
divContent.style.top=margins.top+"px";
divContent.style.width=contentWidth+"px";
divContent.style.height=contentHeight+"px";
divContent.style.overflow="auto";
divContent.style.background="white";
divInner.appendChild(divContent);
bubble.content=divContent;

(function(){
if(pageX-SimileAjax.Graphics._halfArrowWidth-SimileAjax.Graphics._bubblePadding>0&&
pageX+SimileAjax.Graphics._halfArrowWidth+SimileAjax.Graphics._bubblePadding<docWidth){

var left=pageX-Math.round(contentWidth/2)-margins.left;
left=pageX<(docWidth/2)?
Math.max(left,-(margins.left-SimileAjax.Graphics._bubblePadding)):
Math.min(left,docWidth+(margins.right-SimileAjax.Graphics._bubblePadding)-bubbleWidth);

if((orientation&&orientation=="top")||(!orientation&&(pageY-SimileAjax.Graphics._bubblePointOffset-bubbleHeight>0))){
var divImg=document.createElement("div");

divImg.style.left=(pageX-SimileAjax.Graphics._halfArrowWidth-left)+"px";
divImg.style.top=(margins.top+contentHeight)+"px";
setImg(divImg,urlPrefix+"images/bubble-bottom-arrow.png",37,margins.bottom);
divInner.appendChild(divImg);

div.style.left=left+"px";
div.style.top=(pageY-SimileAjax.Graphics._bubblePointOffset-bubbleHeight+
SimileAjax.Graphics._arrowOffsets.bottom)+"px";

return;
}else if((orientation&&orientation=="bottom")||(!orientation&&(pageY+SimileAjax.Graphics._bubblePointOffset+bubbleHeight<docHeight))){
var divImg=document.createElement("div");

divImg.style.left=(pageX-SimileAjax.Graphics._halfArrowWidth-left)+"px";
divImg.style.top="0px";
setImg(divImg,urlPrefix+"images/bubble-top-arrow.png",37,margins.top);
divInner.appendChild(divImg);

div.style.left=left+"px";
div.style.top=(pageY+SimileAjax.Graphics._bubblePointOffset-
SimileAjax.Graphics._arrowOffsets.top)+"px";

return;
}
}

var top=pageY-Math.round(contentHeight/2)-margins.top;
top=pageY<(docHeight/2)?
Math.max(top,-(margins.top-SimileAjax.Graphics._bubblePadding)):
Math.min(top,docHeight+(margins.bottom-SimileAjax.Graphics._bubblePadding)-bubbleHeight);

if((orientation&&orientation=="left")||(!orientation&&(pageX-SimileAjax.Graphics._bubblePointOffset-bubbleWidth>0))){
var divImg=document.createElement("div");

divImg.style.left=(margins.left+contentWidth)+"px";
divImg.style.top=(pageY-SimileAjax.Graphics._halfArrowWidth-top)+"px";
setImg(divImg,urlPrefix+"images/bubble-right-arrow.png",margins.right,37);
divInner.appendChild(divImg);

div.style.left=(pageX-SimileAjax.Graphics._bubblePointOffset-bubbleWidth+
SimileAjax.Graphics._arrowOffsets.right)+"px";
div.style.top=top+"px";
}else if((orientation&&orientation=="right")||(!orientation&&(pageX-SimileAjax.Graphics._bubblePointOffset-bubbleWidth<docWidth))){
var divImg=document.createElement("div");

divImg.style.left="0px";
divImg.style.top=(pageY-SimileAjax.Graphics._halfArrowWidth-top)+"px";
setImg(divImg,urlPrefix+"images/bubble-left-arrow.png",margins.left,37);
divInner.appendChild(divImg);

div.style.left=(pageX+SimileAjax.Graphics._bubblePointOffset-
SimileAjax.Graphics._arrowOffsets.left)+"px";
div.style.top=top+"px";
}
})();

document.body.appendChild(div);

return bubble;
};


SimileAjax.Graphics.createMessageBubble=function(doc){
var containerDiv=doc.createElement("div");
if(SimileAjax.Graphics.pngIsTranslucent){
var topDiv=doc.createElement("div");
topDiv.style.height="33px";
topDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-top-left.png) top left no-repeat";
topDiv.style.paddingLeft="44px";
containerDiv.appendChild(topDiv);

var topRightDiv=doc.createElement("div");
topRightDiv.style.height="33px";
topRightDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-top-right.png) top right no-repeat";
topDiv.appendChild(topRightDiv);

var middleDiv=doc.createElement("div");
middleDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-left.png) top left repeat-y";
middleDiv.style.paddingLeft="44px";
containerDiv.appendChild(middleDiv);

var middleRightDiv=doc.createElement("div");
middleRightDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-right.png) top right repeat-y";
middleRightDiv.style.paddingRight="44px";
middleDiv.appendChild(middleRightDiv);

var contentDiv=doc.createElement("div");
middleRightDiv.appendChild(contentDiv);

var bottomDiv=doc.createElement("div");
bottomDiv.style.height="55px";
bottomDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-bottom-left.png) bottom left no-repeat";
bottomDiv.style.paddingLeft="44px";
containerDiv.appendChild(bottomDiv);

var bottomRightDiv=doc.createElement("div");
bottomRightDiv.style.height="55px";
bottomRightDiv.style.background="url("+SimileAjax.urlPrefix+"images/message-bottom-right.png) bottom right no-repeat";
bottomDiv.appendChild(bottomRightDiv);
}else{
containerDiv.style.border="2px solid #7777AA";
containerDiv.style.padding="20px";
containerDiv.style.background="white";
SimileAjax.Graphics.setOpacity(containerDiv,90);

var contentDiv=doc.createElement("div");
containerDiv.appendChild(contentDiv);
}

return{
containerDiv:containerDiv,
contentDiv:contentDiv
};
};




SimileAjax.Graphics.createAnimation=function(f,from,to,duration,cont){
return new SimileAjax.Graphics._Animation(f,from,to,duration,cont);
};

SimileAjax.Graphics._Animation=function(f,from,to,duration,cont){
this.f=f;
this.cont=(typeof cont=="function")?cont:function(){};

this.from=from;
this.to=to;
this.current=from;

this.duration=duration;
this.start=new Date().getTime();
this.timePassed=0;
};


SimileAjax.Graphics._Animation.prototype.run=function(){
var a=this;
window.setTimeout(function(){a.step();},50);
};


SimileAjax.Graphics._Animation.prototype.step=function(){
this.timePassed+=50;

var timePassedFraction=this.timePassed/this.duration;
var parameterFraction=-Math.cos(timePassedFraction*Math.PI)/2+0.5;
var current=parameterFraction*(this.to-this.from)+this.from;

try{
this.f(current,current-this.current);
}catch(e){
}
this.current=current;

if(this.timePassed<this.duration){
this.run();
}else{
this.f(this.to,0);
this["cont"]();
}
};




SimileAjax.Graphics.createStructuredDataCopyButton=function(image,width,height,createDataFunction){
var div=document.createElement("div");
div.style.position="relative";
div.style.display="inline";
div.style.width=width+"px";
div.style.height=height+"px";
div.style.overflow="hidden";
div.style.margin="2px";

if(SimileAjax.Graphics.pngIsTranslucent){
div.style.background="url("+image+") no-repeat";
}else{
div.style.filter="progid:DXImageTransform.Microsoft.AlphaImageLoader(src='"+image+"', sizingMethod='image')";
}

var style;
if(SimileAjax.Platform.browser.isIE){
style="filter:alpha(opacity=0)";
}else{
style="opacity: 0";
}
div.innerHTML="<textarea rows='1' autocomplete='off' value='none' style='"+style+"' />";

var textarea=div.firstChild;
textarea.style.width=width+"px";
textarea.style.height=height+"px";
textarea.onmousedown=function(evt){
evt=(evt)?evt:((event)?event:null);
if(evt.button==2){
textarea.value=createDataFunction();
textarea.select();
}
};

return div;
};

SimileAjax.Graphics.getFontRenderingContext=function(elmt,width){
return new SimileAjax.Graphics._FontRenderingContext(elmt,width);
};

SimileAjax.Graphics._FontRenderingContext=function(elmt,width){
this._originalElmt=elmt;
this._div=document.createElement("div");
this._div.style.position="absolute";
this._div.style.left="-1000px";
this._div.style.top="-1000px";
if(typeof width=="string"){
this._div.style.width=width;
}else if(typeof width=="number"){
this._div.style.width=width+"px";
}
document.body.appendChild(this._div);
};

SimileAjax.Graphics._FontRenderingContext.prototype.dispose=function(){
document.body.removeChild(this._div);

this._div=null;
this._originalElmt=null;
};

SimileAjax.Graphics._FontRenderingContext.prototype.update=function(){
this._copyStyle();
this._div.innerHTML="A";
this._lineHeight=this._div.offsetHeight;
};

SimileAjax.Graphics._FontRenderingContext.prototype._copyStyle=function(){
try{
var style=window.getComputedStyle(this._originalElmt,"");
this._div.style.fontFamily=style.getPropertyValue("font-family");
this._div.style.fontSize=style.getPropertyValue("font-size");
this._div.style.fontWeight=style.getPropertyValue("font-weight");
this._div.style.fontVariant=style.getPropertyValue("font-variant");
this._div.style.fontStyle=style.getPropertyValue("font-style");
return;
}catch(e){
}

var style=this._originalElmt.currentStyle;
if(style==null){
style=this._originalElmt.runningStyle;
}

this._div.style.fontFamily=style.fontFamily;
this._div.style.fontSize=style.fontSize;
this._div.style.fontWeight=style.fontWeight;
this._div.style.fontVariant=style.fontVariant;
this._div.style.fontStyle=style.fontStyle;
}

SimileAjax.Graphics._FontRenderingContext.prototype.computeSize=function(text){
this._div.innerHTML=text;
return{
width:this._div.offsetWidth,
height:this._div.offsetHeight
};
};

SimileAjax.Graphics._FontRenderingContext.prototype.getLineHeight=function(){
return this._lineHeight;
};


/* history.js */



SimileAjax.History={
maxHistoryLength:10,
historyFile:"__history__.html",
enabled:true,

_initialized:false,
_listeners:new SimileAjax.ListenerQueue(),

_actions:[],
_baseIndex:0,
_currentIndex:0,

_plainDocumentTitle:document.title
};

SimileAjax.History.formatHistoryEntryTitle=function(actionLabel){
return SimileAjax.History._plainDocumentTitle+" {"+actionLabel+"}";
};

SimileAjax.History.initialize=function(){
if(SimileAjax.History._initialized){
return;
}

if(SimileAjax.History.enabled){
var iframe=document.createElement("iframe");
iframe.id="simile-ajax-history";
iframe.style.position="absolute";
iframe.style.width="10px";
iframe.style.height="10px";
iframe.style.top="0px";
iframe.style.left="0px";
iframe.style.visibility="hidden";
iframe.src=SimileAjax.History.historyFile+"?0";

document.body.appendChild(iframe);
SimileAjax.DOM.registerEvent(iframe,"load",SimileAjax.History._handleIFrameOnLoad);

SimileAjax.History._iframe=iframe;
}
SimileAjax.History._initialized=true;
};

SimileAjax.History.addListener=function(listener){
SimileAjax.History.initialize();

SimileAjax.History._listeners.add(listener);
};

SimileAjax.History.removeListener=function(listener){
SimileAjax.History.initialize();

SimileAjax.History._listeners.remove(listener);
};

SimileAjax.History.addAction=function(action){
SimileAjax.History.initialize();

SimileAjax.History._listeners.fire("onBeforePerform",[action]);
window.setTimeout(function(){
try{
action.perform();
SimileAjax.History._listeners.fire("onAfterPerform",[action]);

if(SimileAjax.History.enabled){
SimileAjax.History._actions=SimileAjax.History._actions.slice(
0,SimileAjax.History._currentIndex-SimileAjax.History._baseIndex);

SimileAjax.History._actions.push(action);
SimileAjax.History._currentIndex++;

var diff=SimileAjax.History._actions.length-SimileAjax.History.maxHistoryLength;
if(diff>0){
SimileAjax.History._actions=SimileAjax.History._actions.slice(diff);
SimileAjax.History._baseIndex+=diff;
}

try{
SimileAjax.History._iframe.contentWindow.location.search=
"?"+SimileAjax.History._currentIndex;
}catch(e){

var title=SimileAjax.History.formatHistoryEntryTitle(action.label);
document.title=title;
}
}
}catch(e){
SimileAjax.Debug.exception(e,"Error adding action {"+action.label+"} to history");
}
},0);
};

SimileAjax.History.addLengthyAction=function(perform,undo,label){
SimileAjax.History.addAction({
perform:perform,
undo:undo,
label:label,
uiLayer:SimileAjax.WindowManager.getBaseLayer(),
lengthy:true
});
};

SimileAjax.History._handleIFrameOnLoad=function(){


try{
var q=SimileAjax.History._iframe.contentWindow.location.search;
var c=(q.length==0)?0:Math.max(0,parseInt(q.substr(1)));

var finishUp=function(){
var diff=c-SimileAjax.History._currentIndex;
SimileAjax.History._currentIndex+=diff;
SimileAjax.History._baseIndex+=diff;

SimileAjax.History._iframe.contentWindow.location.search="?"+c;
};

if(c<SimileAjax.History._currentIndex){
SimileAjax.History._listeners.fire("onBeforeUndoSeveral",[]);
window.setTimeout(function(){
while(SimileAjax.History._currentIndex>c&&
SimileAjax.History._currentIndex>SimileAjax.History._baseIndex){

SimileAjax.History._currentIndex--;

var action=SimileAjax.History._actions[SimileAjax.History._currentIndex-SimileAjax.History._baseIndex];

try{
action.undo();
}catch(e){
SimileAjax.Debug.exception(e,"History: Failed to undo action {"+action.label+"}");
}
}

SimileAjax.History._listeners.fire("onAfterUndoSeveral",[]);
finishUp();
},0);
}else if(c>SimileAjax.History._currentIndex){
SimileAjax.History._listeners.fire("onBeforeRedoSeveral",[]);
window.setTimeout(function(){
while(SimileAjax.History._currentIndex<c&&
SimileAjax.History._currentIndex-SimileAjax.History._baseIndex<SimileAjax.History._actions.length){

var action=SimileAjax.History._actions[SimileAjax.History._currentIndex-SimileAjax.History._baseIndex];

try{
action.perform();
}catch(e){
SimileAjax.Debug.exception(e,"History: Failed to redo action {"+action.label+"}");
}

SimileAjax.History._currentIndex++;
}

SimileAjax.History._listeners.fire("onAfterRedoSeveral",[]);
finishUp();
},0);
}else{
var index=SimileAjax.History._currentIndex-SimileAjax.History._baseIndex-1;
var title=(index>=0&&index<SimileAjax.History._actions.length)?
SimileAjax.History.formatHistoryEntryTitle(SimileAjax.History._actions[index].label):
SimileAjax.History._plainDocumentTitle;

SimileAjax.History._iframe.contentWindow.document.title=title;
document.title=title;
}
}catch(e){

}
};

SimileAjax.History.getNextUndoAction=function(){
try{
var index=SimileAjax.History._currentIndex-SimileAjax.History._baseIndex-1;
return SimileAjax.History._actions[index];
}catch(e){
return null;
}
};

SimileAjax.History.getNextRedoAction=function(){
try{
var index=SimileAjax.History._currentIndex-SimileAjax.History._baseIndex;
return SimileAjax.History._actions[index];
}catch(e){
return null;
}
};


/* html.js */



SimileAjax.HTML=new Object();

SimileAjax.HTML._e2uHash={};
(function(){
e2uHash=SimileAjax.HTML._e2uHash;
e2uHash['nbsp']='\u00A0[space]';
e2uHash['iexcl']='\u00A1';
e2uHash['cent']='\u00A2';
e2uHash['pound']='\u00A3';
e2uHash['curren']='\u00A4';
e2uHash['yen']='\u00A5';
e2uHash['brvbar']='\u00A6';
e2uHash['sect']='\u00A7';
e2uHash['uml']='\u00A8';
e2uHash['copy']='\u00A9';
e2uHash['ordf']='\u00AA';
e2uHash['laquo']='\u00AB';
e2uHash['not']='\u00AC';
e2uHash['shy']='\u00AD';
e2uHash['reg']='\u00AE';
e2uHash['macr']='\u00AF';
e2uHash['deg']='\u00B0';
e2uHash['plusmn']='\u00B1';
e2uHash['sup2']='\u00B2';
e2uHash['sup3']='\u00B3';
e2uHash['acute']='\u00B4';
e2uHash['micro']='\u00B5';
e2uHash['para']='\u00B6';
e2uHash['middot']='\u00B7';
e2uHash['cedil']='\u00B8';
e2uHash['sup1']='\u00B9';
e2uHash['ordm']='\u00BA';
e2uHash['raquo']='\u00BB';
e2uHash['frac14']='\u00BC';
e2uHash['frac12']='\u00BD';
e2uHash['frac34']='\u00BE';
e2uHash['iquest']='\u00BF';
e2uHash['Agrave']='\u00C0';
e2uHash['Aacute']='\u00C1';
e2uHash['Acirc']='\u00C2';
e2uHash['Atilde']='\u00C3';
e2uHash['Auml']='\u00C4';
e2uHash['Aring']='\u00C5';
e2uHash['AElig']='\u00C6';
e2uHash['Ccedil']='\u00C7';
e2uHash['Egrave']='\u00C8';
e2uHash['Eacute']='\u00C9';
e2uHash['Ecirc']='\u00CA';
e2uHash['Euml']='\u00CB';
e2uHash['Igrave']='\u00CC';
e2uHash['Iacute']='\u00CD';
e2uHash['Icirc']='\u00CE';
e2uHash['Iuml']='\u00CF';
e2uHash['ETH']='\u00D0';
e2uHash['Ntilde']='\u00D1';
e2uHash['Ograve']='\u00D2';
e2uHash['Oacute']='\u00D3';
e2uHash['Ocirc']='\u00D4';
e2uHash['Otilde']='\u00D5';
e2uHash['Ouml']='\u00D6';
e2uHash['times']='\u00D7';
e2uHash['Oslash']='\u00D8';
e2uHash['Ugrave']='\u00D9';
e2uHash['Uacute']='\u00DA';
e2uHash['Ucirc']='\u00DB';
e2uHash['Uuml']='\u00DC';
e2uHash['Yacute']='\u00DD';
e2uHash['THORN']='\u00DE';
e2uHash['szlig']='\u00DF';
e2uHash['agrave']='\u00E0';
e2uHash['aacute']='\u00E1';
e2uHash['acirc']='\u00E2';
e2uHash['atilde']='\u00E3';
e2uHash['auml']='\u00E4';
e2uHash['aring']='\u00E5';
e2uHash['aelig']='\u00E6';
e2uHash['ccedil']='\u00E7';
e2uHash['egrave']='\u00E8';
e2uHash['eacute']='\u00E9';
e2uHash['ecirc']='\u00EA';
e2uHash['euml']='\u00EB';
e2uHash['igrave']='\u00EC';
e2uHash['iacute']='\u00ED';
e2uHash['icirc']='\u00EE';
e2uHash['iuml']='\u00EF';
e2uHash['eth']='\u00F0';
e2uHash['ntilde']='\u00F1';
e2uHash['ograve']='\u00F2';
e2uHash['oacute']='\u00F3';
e2uHash['ocirc']='\u00F4';
e2uHash['otilde']='\u00F5';
e2uHash['ouml']='\u00F6';
e2uHash['divide']='\u00F7';
e2uHash['oslash']='\u00F8';
e2uHash['ugrave']='\u00F9';
e2uHash['uacute']='\u00FA';
e2uHash['ucirc']='\u00FB';
e2uHash['uuml']='\u00FC';
e2uHash['yacute']='\u00FD';
e2uHash['thorn']='\u00FE';
e2uHash['yuml']='\u00FF';
e2uHash['quot']='\u0022';
e2uHash['amp']='\u0026';
e2uHash['lt']='\u003C';
e2uHash['gt']='\u003E';
e2uHash['OElig']='';
e2uHash['oelig']='\u0153';
e2uHash['Scaron']='\u0160';
e2uHash['scaron']='\u0161';
e2uHash['Yuml']='\u0178';
e2uHash['circ']='\u02C6';
e2uHash['tilde']='\u02DC';
e2uHash['ensp']='\u2002';
e2uHash['emsp']='\u2003';
e2uHash['thinsp']='\u2009';
e2uHash['zwnj']='\u200C';
e2uHash['zwj']='\u200D';
e2uHash['lrm']='\u200E';
e2uHash['rlm']='\u200F';
e2uHash['ndash']='\u2013';
e2uHash['mdash']='\u2014';
e2uHash['lsquo']='\u2018';
e2uHash['rsquo']='\u2019';
e2uHash['sbquo']='\u201A';
e2uHash['ldquo']='\u201C';
e2uHash['rdquo']='\u201D';
e2uHash['bdquo']='\u201E';
e2uHash['dagger']='\u2020';
e2uHash['Dagger']='\u2021';
e2uHash['permil']='\u2030';
e2uHash['lsaquo']='\u2039';
e2uHash['rsaquo']='\u203A';
e2uHash['euro']='\u20AC';
e2uHash['fnof']='\u0192';
e2uHash['Alpha']='\u0391';
e2uHash['Beta']='\u0392';
e2uHash['Gamma']='\u0393';
e2uHash['Delta']='\u0394';
e2uHash['Epsilon']='\u0395';
e2uHash['Zeta']='\u0396';
e2uHash['Eta']='\u0397';
e2uHash['Theta']='\u0398';
e2uHash['Iota']='\u0399';
e2uHash['Kappa']='\u039A';
e2uHash['Lambda']='\u039B';
e2uHash['Mu']='\u039C';
e2uHash['Nu']='\u039D';
e2uHash['Xi']='\u039E';
e2uHash['Omicron']='\u039F';
e2uHash['Pi']='\u03A0';
e2uHash['Rho']='\u03A1';
e2uHash['Sigma']='\u03A3';
e2uHash['Tau']='\u03A4';
e2uHash['Upsilon']='\u03A5';
e2uHash['Phi']='\u03A6';
e2uHash['Chi']='\u03A7';
e2uHash['Psi']='\u03A8';
e2uHash['Omega']='\u03A9';
e2uHash['alpha']='\u03B1';
e2uHash['beta']='\u03B2';
e2uHash['gamma']='\u03B3';
e2uHash['delta']='\u03B4';
e2uHash['epsilon']='\u03B5';
e2uHash['zeta']='\u03B6';
e2uHash['eta']='\u03B7';
e2uHash['theta']='\u03B8';
e2uHash['iota']='\u03B9';
e2uHash['kappa']='\u03BA';
e2uHash['lambda']='\u03BB';
e2uHash['mu']='\u03BC';
e2uHash['nu']='\u03BD';
e2uHash['xi']='\u03BE';
e2uHash['omicron']='\u03BF';
e2uHash['pi']='\u03C0';
e2uHash['rho']='\u03C1';
e2uHash['sigmaf']='\u03C2';
e2uHash['sigma']='\u03C3';
e2uHash['tau']='\u03C4';
e2uHash['upsilon']='\u03C5';
e2uHash['phi']='\u03C6';
e2uHash['chi']='\u03C7';
e2uHash['psi']='\u03C8';
e2uHash['omega']='\u03C9';
e2uHash['thetasym']='\u03D1';
e2uHash['upsih']='\u03D2';
e2uHash['piv']='\u03D6';
e2uHash['bull']='\u2022';
e2uHash['hellip']='\u2026';
e2uHash['prime']='\u2032';
e2uHash['Prime']='\u2033';
e2uHash['oline']='\u203E';
e2uHash['frasl']='\u2044';
e2uHash['weierp']='\u2118';
e2uHash['image']='\u2111';
e2uHash['real']='\u211C';
e2uHash['trade']='\u2122';
e2uHash['alefsym']='\u2135';
e2uHash['larr']='\u2190';
e2uHash['uarr']='\u2191';
e2uHash['rarr']='\u2192';
e2uHash['darr']='\u2193';
e2uHash['harr']='\u2194';
e2uHash['crarr']='\u21B5';
e2uHash['lArr']='\u21D0';
e2uHash['uArr']='\u21D1';
e2uHash['rArr']='\u21D2';
e2uHash['dArr']='\u21D3';
e2uHash['hArr']='\u21D4';
e2uHash['forall']='\u2200';
e2uHash['part']='\u2202';
e2uHash['exist']='\u2203';
e2uHash['empty']='\u2205';
e2uHash['nabla']='\u2207';
e2uHash['isin']='\u2208';
e2uHash['notin']='\u2209';
e2uHash['ni']='\u220B';
e2uHash['prod']='\u220F';
e2uHash['sum']='\u2211';
e2uHash['minus']='\u2212';
e2uHash['lowast']='\u2217';
e2uHash['radic']='\u221A';
e2uHash['prop']='\u221D';
e2uHash['infin']='\u221E';
e2uHash['ang']='\u2220';
e2uHash['and']='\u2227';
e2uHash['or']='\u2228';
e2uHash['cap']='\u2229';
e2uHash['cup']='\u222A';
e2uHash['int']='\u222B';
e2uHash['there4']='\u2234';
e2uHash['sim']='\u223C';
e2uHash['cong']='\u2245';
e2uHash['asymp']='\u2248';
e2uHash['ne']='\u2260';
e2uHash['equiv']='\u2261';
e2uHash['le']='\u2264';
e2uHash['ge']='\u2265';
e2uHash['sub']='\u2282';
e2uHash['sup']='\u2283';
e2uHash['nsub']='\u2284';
e2uHash['sube']='\u2286';
e2uHash['supe']='\u2287';
e2uHash['oplus']='\u2295';
e2uHash['otimes']='\u2297';
e2uHash['perp']='\u22A5';
e2uHash['sdot']='\u22C5';
e2uHash['lceil']='\u2308';
e2uHash['rceil']='\u2309';
e2uHash['lfloor']='\u230A';
e2uHash['rfloor']='\u230B';
e2uHash['lang']='\u2329';
e2uHash['rang']='\u232A';
e2uHash['loz']='\u25CA';
e2uHash['spades']='\u2660';
e2uHash['clubs']='\u2663';
e2uHash['hearts']='\u2665';
e2uHash['diams']='\u2666';
})();

SimileAjax.HTML.deEntify=function(s){
e2uHash=SimileAjax.HTML._e2uHash;

var re=/&(\w+?);/;
while(re.test(s)){
var m=s.match(re);
s=s.replace(re,e2uHash[m[1]]);
}
return s;
};

/* jquery-1.1.3.1.js */


eval(function(p,a,c,k,e,r){e=function(c){return(c<a?'':e(parseInt(c/a)))+((c=c%a)>35?String.fromCharCode(c+29):c.toString(36))};if(!''.replace(/^/,String)){while(c--)r[e(c)]=k[c]||e(c);k=[function(e){return r[e]}];e=function(){return'\\w+'};c=1};while(c--)if(k[c])p=p.replace(new RegExp('\\b'+e(c)+'\\b','g'),k[c]);return p}('7(1g 18.6=="I"){18.I=18.I;u 6=q(a,c){7(18==9||!9.3X)v 14 6(a,c);v 9.3X(a,c)};7(1g $!="I")6.1I$=$;u $=6;6.11=6.8r={3X:q(a,c){a=a||P;7(6.16(a))v 14 6(P)[6.11.1G?"1G":"1W"](a);7(1g a=="1s"){u m=/^[^<]*(<(.|\\s)+>)[^>]*$/.1V(a);7(m)a=6.31([m[1]]);B v 14 6(c).1L(a)}v 9.4E(a.15==2b&&a||(a.3C||a.C&&a!=18&&!a.1q&&a[0]!=I&&a[0].1q)&&6.2L(a)||[a])},3C:"1.1.3.1",7W:q(){v 9.C},C:0,1M:q(a){v a==I?6.2L(9):9[a]},1Z:q(a){u b=6(a);b.5q=9;v b},4E:q(a){9.C=0;[].R.O(9,a);v 9},F:q(a,b){v 6.F(9,a,b)},2p:q(a){u b=-1;9.F(q(i){7(9==a)b=i});v b},1b:q(f,d,e){u c=f;7(f.15==33)7(d==I)v 9.C&&6[e||"1b"](9[0],f)||I;B{c={};c[f]=d}v 9.F(q(a){E(u b V c)6.1b(e?9.T:9,b,6.4H(9,c[b],e,a,b))})},1f:q(b,a){v 9.1b(b,a,"2z")},2A:q(e){7(1g e=="1s")v 9.2Y().3e(P.66(e));u t="";6.F(e||9,q(){6.F(9.2S,q(){7(9.1q!=8)t+=9.1q!=1?9.5R:6.11.2A([9])})});v t},8b:q(){u a,1S=19;v 9.F(q(){7(!a)a=6.31(1S,9.2O);u b=a[0].3s(K);9.L.2K(b,9);1v(b.1d)b=b.1d;b.4g(9)})},3e:q(){v 9.2F(19,K,1,q(a){9.4g(a)})},5w:q(){v 9.2F(19,K,-1,q(a){9.2K(a,9.1d)})},5t:q(){v 9.2F(19,N,1,q(a){9.L.2K(a,9)})},5s:q(){v 9.2F(19,N,-1,q(a){9.L.2K(a,9.1X)})},2U:q(){v 9.5q||6([])},1L:q(t){u b=6.3k(9,q(a){v 6.1L(t,a)});v 9.1Z(/[^+>] [^+>]/.17(t)||t.J("..")>-1?6.5g(b):b)},7x:q(e){u d=9.1A(9.1L("*"));d.F(q(){9.1I$1a={};E(u a V 9.$1a)9.1I$1a[a]=6.1c({},9.$1a[a])}).3U();u r=9.1Z(6.3k(9,q(a){v a.3s(e!=I?e:K)}));d.F(q(){u b=9.1I$1a;E(u a V b)E(u c V b[a])6.S.1A(9,a,b[a][c],b[a][c].W);9.1I$1a=H});v r},1i:q(t){v 9.1Z(6.16(t)&&6.2s(9,q(b,a){v t.O(b,[a])})||6.2x(t,9))},4Y:q(t){v 9.1Z(t.15==33&&6.2x(t,9,K)||6.2s(9,q(a){v(t.15==2b||t.3C)?6.2w(a,t)<0:a!=t}))},1A:q(t){v 9.1Z(6.1T(9.1M(),t.15==33?6(t).1M():t.C!=I&&(!t.Q||t.Q=="6Z")?t:[t]))},37:q(a){v a?6.2x(a,9).C>0:N},6R:q(a){v a==I?(9.C?9[0].2v:H):9.1b("2v",a)},3F:q(a){v a==I?(9.C?9[0].27:H):9.2Y().3e(a)},2F:q(f,d,g,e){u c=9.C>1,a;v 9.F(q(){7(!a){a=6.31(f,9.2O);7(g<0)a.6E()}u b=9;7(d&&6.Q(9,"1r")&&6.Q(a[0],"2V"))b=9.3R("1z")[0]||9.4g(P.5h("1z"));6.F(a,q(){e.O(b,[c?9.3s(K):9])})})}};6.1c=6.11.1c=q(){u c=19[0],a=1;7(19.C==1){c=9;a=0}u b;1v((b=19[a++])!=H)E(u i V b)c[i]=b[i];v c};6.1c({6n:q(){7(6.1I$)$=6.1I$;v 6},16:q(a){v!!a&&1g a!="1s"&&!a.Q&&a.15!=2b&&/q/i.17(a+"")},40:q(a){v a.4z&&a.2O&&!a.2O.4y},Q:q(b,a){v b.Q&&b.Q.1D()==a.1D()},F:q(a,b,c){7(a.C==I)E(u i V a)b.O(a[i],c||[i,a[i]]);B E(u i=0,4x=a.C;i<4x;i++)7(b.O(a[i],c||[i,a[i]])===N)1F;v a},4H:q(c,b,d,e,a){7(6.16(b))b=b.3D(c,[e]);u f=/z-?2p|5Y-?8p|1e|5U|8i-?1u/i;v b&&b.15==3y&&d=="2z"&&!f.17(a)?b+"4o":b},12:{1A:q(b,c){6.F(c.2R(/\\s+/),q(i,a){7(!6.12.3w(b.12,a))b.12+=(b.12?" ":"")+a})},1E:q(b,c){b.12=c!=I?6.2s(b.12.2R(/\\s+/),q(a){v!6.12.3w(c,a)}).5M(" "):""},3w:q(t,c){v 6.2w(c,(t.12||t).3v().2R(/\\s+/))>-1}},4m:q(e,o,f){E(u i V o){e.T["2N"+i]=e.T[i];e.T[i]=o[i]}f.O(e,[]);E(u i V o)e.T[i]=e.T["2N"+i]},1f:q(e,p){7(p=="1u"||p=="29"){u b={},3r,3p,d=["83","81","80","7Y"];6.F(d,q(){b["7V"+9]=0;b["7T"+9+"7S"]=0});6.4m(e,b,q(){7(6(e).37(\':4f\')){3r=e.7Q;3p=e.7O}B{e=6(e.3s(K)).1L(":4b").5v("2B").2U().1f({48:"1y",3i:"7L",U:"2h",7K:"0",7I:"0"}).5o(e.L)[0];u a=6.1f(e.L,"3i")||"3n";7(a=="3n")e.L.T.3i="7G";3r=e.7E;3p=e.7D;7(a=="3n")e.L.T.3i="3n";e.L.3q(e)}});v p=="1u"?3r:3p}v 6.2z(e,p)},2z:q(e,a,d){u g;7(a=="1e"&&6.M.1h){g=6.1b(e.T,"1e");v g==""?"1":g}7(a.3t(/3x/i))a=6.1U;7(!d&&e.T[a])g=e.T[a];B 7(P.3f&&P.3f.3Y){7(a.3t(/3x/i))a="3x";a=a.1o(/([A-Z])/g,"-$1").2H();u b=P.3f.3Y(e,H);7(b)g=b.57(a);B 7(a=="U")g="1P";B 6.4m(e,{U:"2h"},q(){u c=P.3f.3Y(9,"");g=c&&c.57(a)||""})}B 7(e.3S){u f=a.1o(/\\-(\\w)/g,q(m,c){v c.1D()});g=e.3S[a]||e.3S[f]}v g},31:q(a,c){u r=[];c=c||P;6.F(a,q(i,b){7(!b)v;7(b.15==3y)b=b.3v();7(1g b=="1s"){u s=6.2C(b).2H(),1x=c.5h("1x"),1N=[];u a=!s.J("<1H")&&[1,"<2y>","</2y>"]||!s.J("<7g")&&[1,"<52>","</52>"]||(!s.J("<7c")||!s.J("<1z")||!s.J("<7a")||!s.J("<78"))&&[1,"<1r>","</1r>"]||!s.J("<2V")&&[2,"<1r><1z>","</1z></1r>"]||(!s.J("<75")||!s.J("<74"))&&[3,"<1r><1z><2V>","</2V></1z></1r>"]||!s.J("<73")&&[2,"<1r><4W>","</4W></1r>"]||[0,"",""];1x.27=a[1]+b+a[2];1v(a[0]--)1x=1x.1d;7(6.M.1h){7(!s.J("<1r")&&s.J("<1z")<0)1N=1x.1d&&1x.1d.2S;B 7(a[1]=="<1r>"&&s.J("<1z")<0)1N=1x.2S;E(u n=1N.C-1;n>=0;--n)7(6.Q(1N[n],"1z")&&!1N[n].2S.C)1N[n].L.3q(1N[n])}b=6.2L(1x.2S)}7(0===b.C&&(!6.Q(b,"34")&&!6.Q(b,"2y")))v;7(b[0]==I||6.Q(b,"34")||b.71)r.R(b);B r=6.1T(r,b)});v r},1b:q(c,d,a){u e=6.40(c)?{}:6.3H;7(e[d]){7(a!=I)c[e[d]]=a;v c[e[d]]}B 7(a==I&&6.M.1h&&6.Q(c,"34")&&(d=="70"||d=="6Y"))v c.6W(d).5R;B 7(c.4z){7(a!=I)c.6U(d,a);7(6.M.1h&&/4M|2u/.17(d)&&!6.40(c))v c.35(d,2);v c.35(d)}B{7(d=="1e"&&6.M.1h){7(a!=I){c.5U=1;c.1i=(c.1i||"").1o(/4L\\([^)]*\\)/,"")+(39(a).3v()=="6M"?"":"4L(1e="+a*4X+")")}v c.1i?(39(c.1i.3t(/1e=([^)]*)/)[1])/4X).3v():""}d=d.1o(/-([a-z])/6K,q(z,b){v b.1D()});7(a!=I)c[d]=a;v c[d]}},2C:q(t){v t.1o(/^\\s+|\\s+$/g,"")},2L:q(a){u r=[];7(1g a!="6I")E(u i=0,26=a.C;i<26;i++)r.R(a[i]);B r=a.51(0);v r},2w:q(b,a){E(u i=0,26=a.C;i<26;i++)7(a[i]==b)v i;v-1},1T:q(a,b){E(u i=0;b[i];i++)a.R(b[i]);v a},5g:q(a){u r=[],3P=6.1k++;E(u i=0,4G=a.C;i<4G;i++)7(3P!=a[i].1k){a[i].1k=3P;r.R(a[i])}v r},1k:0,2s:q(c,b,d){7(1g b=="1s")b=14 45("a","i","v "+b);u a=[];E(u i=0,30=c.C;i<30;i++)7(!d&&b(c[i],i)||d&&!b(c[i],i))a.R(c[i]);v a},3k:q(c,b){7(1g b=="1s")b=14 45("a","v "+b);u d=[];E(u i=0,30=c.C;i<30;i++){u a=b(c[i],i);7(a!==H&&a!=I){7(a.15!=2b)a=[a];d=d.6v(a)}}v d}});14 q(){u b=6u.6t.2H();6.M={4D:(b.3t(/.+(?:6s|6q|6o|6m)[\\/: ]([\\d.]+)/)||[])[1],20:/5l/.17(b),2a:/2a/.17(b),1h:/1h/.17(b)&&!/2a/.17(b),3j:/3j/.17(b)&&!/(6h|5l)/.17(b)};6.6g=!6.M.1h||P.6f=="6c";6.1U=6.M.1h?"1U":"5x",6.3H={"E":"68","67":"12","3x":6.1U,5x:6.1U,1U:6.1U,27:"27",12:"12",2v:"2v",2r:"2r",2B:"2B",65:"63",2T:"2T",62:"5Z"}};6.F({4v:"a.L",4p:"6.4p(a)",8o:"6.22(a,2,\'1X\')",8n:"6.22(a,2,\'4t\')",8k:"6.4q(a.L.1d,a)",8h:"6.4q(a.1d)"},q(i,n){6.11[i]=q(a){u b=6.3k(9,n);7(a&&1g a=="1s")b=6.2x(a,b);v 9.1Z(b)}});6.F({5o:"3e",8g:"5w",2K:"5t",8f:"5s"},q(i,n){6.11[i]=q(){u a=19;v 9.F(q(){E(u j=0,26=a.C;j<26;j++)6(a[j])[n](9)})}});6.F({5v:q(a){6.1b(9,a,"");9.8d(a)},8c:q(c){6.12.1A(9,c)},88:q(c){6.12.1E(9,c)},87:q(c){6.12[6.12.3w(9,c)?"1E":"1A"](9,c)},1E:q(a){7(!a||6.1i(a,[9]).r.C)9.L.3q(9)},2Y:q(){1v(9.1d)9.3q(9.1d)}},q(i,n){6.11[i]=q(){v 9.F(n,19)}});6.F(["5Q","5P","5O","5N"],q(i,n){6.11[n]=q(a,b){v 9.1i(":"+n+"("+a+")",b)}});6.F(["1u","29"],q(i,n){6.11[n]=q(h){v h==I?(9.C?6.1f(9[0],n):H):9.1f(n,h.15==33?h:h+"4o")}});6.1c({4n:{"":"m[2]==\'*\'||6.Q(a,m[2])","#":"a.35(\'2m\')==m[2]",":":{5P:"i<m[3]-0",5O:"i>m[3]-0",22:"m[3]-0==i",5Q:"m[3]-0==i",2Q:"i==0",2P:"i==r.C-1",5L:"i%2==0",5K:"i%2","2Q-3u":"a.L.3R(\'*\')[0]==a","2P-3u":"6.22(a.L.5J,1,\'4t\')==a","86-3u":"!6.22(a.L.5J,2,\'4t\')",4v:"a.1d",2Y:"!a.1d",5N:"(a.5H||a.85||\'\').J(m[3])>=0",4f:\'"1y"!=a.G&&6.1f(a,"U")!="1P"&&6.1f(a,"48")!="1y"\',1y:\'"1y"==a.G||6.1f(a,"U")=="1P"||6.1f(a,"48")=="1y"\',84:"!a.2r",2r:"a.2r",2B:"a.2B",2T:"a.2T||6.1b(a,\'2T\')",2A:"\'2A\'==a.G",4b:"\'4b\'==a.G",5F:"\'5F\'==a.G",4l:"\'4l\'==a.G",5E:"\'5E\'==a.G",4k:"\'4k\'==a.G",5D:"\'5D\'==a.G",5C:"\'5C\'==a.G",1J:\'"1J"==a.G||6.Q(a,"1J")\',5B:"/5B|2y|82|1J/i.17(a.Q)"},"[":"6.1L(m[2],a).C"},5A:[/^\\[ *(@)([\\w-]+) *([!*$^~=]*) *(\'?"?)(.*?)\\4 *\\]/,/^(\\[)\\s*(.*?(\\[.*?\\])?[^[]*?)\\s*\\]/,/^(:)([\\w-]+)\\("?\'?(.*?(\\(.*?\\))?[^(]*?)"?\'?\\)/,14 3o("^([:.#]*)("+(6.2J=6.M.20&&6.M.4D<"3.0.0"?"\\\\w":"(?:[\\\\w\\7Z-\\7X*1I-]|\\\\\\\\.)")+"+)")],2x:q(a,c,b){u d,1K=[];1v(a&&a!=d){d=a;u f=6.1i(a,c,b);a=f.t.1o(/^\\s*,\\s*/,"");1K=b?c=f.r:6.1T(1K,f.r)}v 1K},1L:q(t,l){7(1g t!="1s")v[t];7(l&&!l.1q)l=H;l=l||P;7(!t.J("//")){l=l.4h;t=t.2G(2,t.C)}B 7(!t.J("/")&&!l.2O){l=l.4h;t=t.2G(1,t.C);7(t.J("/")>=1)t=t.2G(t.J("/"),t.C)}u b=[l],2j=[],2P;1v(t&&2P!=t){u r=[];2P=t;t=6.2C(t).1o(/^\\/\\//,"");u k=N;u g=14 3o("^[/>]\\\\s*("+6.2J+"+)");u m=g.1V(t);7(m){u o=m[1].1D();E(u i=0;b[i];i++)E(u c=b[i].1d;c;c=c.1X)7(c.1q==1&&(o=="*"||c.Q.1D()==o.1D()))r.R(c);b=r;t=t.1o(g,"");7(t.J(" ")==0)7R;k=K}B{g=/^((\\/?\\.\\.)|([>\\/+~]))\\s*([a-z]*)/i;7((m=g.1V(t))!=H){r=[];u o=m[4],1k=6.1k++;m=m[1];E(u j=0,2e=b.C;j<2e;j++)7(m.J("..")<0){u n=m=="~"||m=="+"?b[j].1X:b[j].1d;E(;n;n=n.1X)7(n.1q==1){7(m=="~"&&n.1k==1k)1F;7(!o||n.Q.1D()==o.1D()){7(m=="~")n.1k=1k;r.R(n)}7(m=="+")1F}}B r.R(b[j].L);b=r;t=6.2C(t.1o(g,""));k=K}}7(t&&!k){7(!t.J(",")){7(l==b[0])b.4e();2j=6.1T(2j,b);r=b=[l];t=" "+t.2G(1,t.C)}B{u h=14 3o("^("+6.2J+"+)(#)("+6.2J+"+)");u m=h.1V(t);7(m){m=[0,m[2],m[3],m[1]]}B{h=14 3o("^([#.]?)("+6.2J+"*)");m=h.1V(t)}m[2]=m[2].1o(/\\\\/g,"");u f=b[b.C-1];7(m[1]=="#"&&f&&f.4d){u p=f.4d(m[2]);7((6.M.1h||6.M.2a)&&p&&1g p.2m=="1s"&&p.2m!=m[2])p=6(\'[@2m="\'+m[2]+\'"]\',f)[0];b=r=p&&(!m[3]||6.Q(p,m[3]))?[p]:[]}B{E(u i=0;b[i];i++){u a=m[1]!=""||m[0]==""?"*":m[2];7(a=="*"&&b[i].Q.2H()=="7P")a="2E";r=6.1T(r,b[i].3R(a))}7(m[1]==".")r=6.4c(r,m[2]);7(m[1]=="#"){u e=[];E(u i=0;r[i];i++)7(r[i].35("2m")==m[2]){e=[r[i]];1F}r=e}b=r}t=t.1o(h,"")}}7(t){u d=6.1i(t,r);b=r=d.r;t=6.2C(d.t)}}7(t)b=[];7(b&&l==b[0])b.4e();2j=6.1T(2j,b);v 2j},4c:q(r,m,a){m=" "+m+" ";u b=[];E(u i=0;r[i];i++){u c=(" "+r[i].12+" ").J(m)>=0;7(!a&&c||a&&!c)b.R(r[i])}v b},1i:q(t,r,h){u d;1v(t&&t!=d){d=t;u p=6.5A,m;E(u i=0;p[i];i++){m=p[i].1V(t);7(m){t=t.7N(m[0].C);m[2]=m[2].1o(/\\\\/g,"");1F}}7(!m)1F;7(m[1]==":"&&m[2]=="4Y")r=6.1i(m[3],r,K).r;B 7(m[1]==".")r=6.4c(r,m[2],h);B 7(m[1]=="@"){u g=[],G=m[3];E(u i=0,2e=r.C;i<2e;i++){u a=r[i],z=a[6.3H[m[2]]||m[2]];7(z==H||/4M|2u/.17(m[2]))z=6.1b(a,m[2])||\'\';7((G==""&&!!z||G=="="&&z==m[5]||G=="!="&&z!=m[5]||G=="^="&&z&&!z.J(m[5])||G=="$="&&z.2G(z.C-m[5].C)==m[5]||(G=="*="||G=="~=")&&z.J(m[5])>=0)^h)g.R(a)}r=g}B 7(m[1]==":"&&m[2]=="22-3u"){u e=6.1k++,g=[],17=/(\\d*)n\\+?(\\d*)/.1V(m[3]=="5L"&&"2n"||m[3]=="5K"&&"2n+1"||!/\\D/.17(m[3])&&"n+"+m[3]||m[3]),2Q=(17[1]||1)-0,d=17[2]-0;E(u i=0,2e=r.C;i<2e;i++){u j=r[i],L=j.L;7(e!=L.1k){u c=1;E(u n=L.1d;n;n=n.1X)7(n.1q==1)n.4a=c++;L.1k=e}u b=N;7(2Q==1){7(d==0||j.4a==d)b=K}B 7((j.4a+d)%2Q==0)b=K;7(b^h)g.R(j)}r=g}B{u f=6.4n[m[1]];7(1g f!="1s")f=6.4n[m[1]][m[2]];49("f = q(a,i){v "+f+"}");r=6.2s(r,f,h)}}v{r:r,t:t}},4p:q(c){u b=[];u a=c.L;1v(a&&a!=P){b.R(a);a=a.L}v b},22:q(a,e,c,b){e=e||1;u d=0;E(;a;a=a[c])7(a.1q==1&&++d==e)1F;v a},4q:q(n,a){u r=[];E(;n;n=n.1X){7(n.1q==1&&(!a||n!=a))r.R(n)}v r}});6.S={1A:q(d,e,c,b){7(6.M.1h&&d.3m!=I)d=18;7(!c.1Q)c.1Q=9.1Q++;7(b!=I){u f=c;c=q(){v f.O(9,19)};c.W=b;c.1Q=f.1Q}7(!d.$1a)d.$1a={};7(!d.$1p)d.$1p=q(){u a;7(1g 6=="I"||6.S.47)v a;a=6.S.1p.O(d,19);v a};u g=d.$1a[e];7(!g){g=d.$1a[e]={};7(d.46)d.46(e,d.$1p,N);B d.7M("5r"+e,d.$1p)}g[c.1Q]=c;7(!9.Y[e])9.Y[e]=[];7(6.2w(d,9.Y[e])==-1)9.Y[e].R(d)},1Q:1,Y:{},1E:q(b,c,a){u d=b.$1a,1Y,2p;7(d){7(c&&c.G){a=c.44;c=c.G}7(!c){E(c V d)9.1E(b,c)}B 7(d[c]){7(a)3l d[c][a.1Q];B E(a V b.$1a[c])3l d[c][a];E(1Y V d[c])1F;7(!1Y){7(b.43)b.43(c,b.$1p,N);B b.7J("5r"+c,b.$1p);1Y=H;3l d[c];1v(9.Y[c]&&((2p=6.2w(b,9.Y[c]))>=0))3l 9.Y[c][2p]}}E(1Y V d)1F;7(!1Y)b.$1p=b.$1a=H}},1t:q(c,b,d){b=6.2L(b||[]);7(!d)6.F(9.Y[c]||[],q(){6.S.1t(c,b,9)});B{u a,1Y,11=6.16(d[c]||H);b.5p(9.42({G:c,1O:d}));7(6.16(d.$1p)&&(a=d.$1p.O(d,b))!==N)9.47=K;7(11&&a!==N&&!6.Q(d,\'a\'))d[c]();9.47=N}},1p:q(b){u a;b=6.S.42(b||18.S||{});u c=9.$1a&&9.$1a[b.G],1S=[].51.3D(19,1);1S.5p(b);E(u j V c){1S[0].44=c[j];1S[0].W=c[j].W;7(c[j].O(9,1S)===N){b.2d();b.2D();a=N}}7(6.M.1h)b.1O=b.2d=b.2D=b.44=b.W=H;v a},42:q(c){u a=c;c=6.1c({},a);c.2d=q(){7(a.2d)v a.2d();a.7H=N};c.2D=q(){7(a.2D)v a.2D();a.7F=K};7(!c.1O&&c.5n)c.1O=c.5n;7(6.M.20&&c.1O.1q==3)c.1O=a.1O.L;7(!c.41&&c.4j)c.41=c.4j==c.1O?c.7C:c.4j;7(c.5k==H&&c.5j!=H){u e=P.4h,b=P.4y;c.5k=c.5j+(e&&e.5i||b.5i);c.7z=c.7y+(e&&e.5f||b.5f)}7(!c.3h&&(c.5e||c.5d))c.3h=c.5e||c.5d;7(!c.5c&&c.5b)c.5c=c.5b;7(!c.3h&&c.1J)c.3h=(c.1J&1?1:(c.1J&2?3:(c.1J&4?2:0)));v c}};6.11.1c({3g:q(c,a,b){v c=="3z"?9.3Z(c,a,b):9.F(q(){6.S.1A(9,c,b||a,b&&a)})},3Z:q(d,b,c){v 9.F(q(){6.S.1A(9,d,q(a){6(9).3U(a);v(c||b).O(9,19)},c&&b)})},3U:q(a,b){v 9.F(q(){6.S.1E(9,a,b)})},1t:q(a,b){v 9.F(q(){6.S.1t(a,b,9)})},1R:q(){u a=19;v 9.5a(q(e){9.4u=0==9.4u?1:0;e.2d();v a[9.4u].O(9,[e])||N})},7w:q(f,g){q 3W(e){u p=e.41;1v(p&&p!=9)2g{p=p.L}25(e){p=9};7(p==9)v N;v(e.G=="3V"?f:g).O(9,[e])}v 9.3V(3W).59(3W)},1G:q(f){7(6.3d)f.O(P,[6]);B 6.2q.R(q(){v f.O(9,[6])});v 9}});6.1c({3d:N,2q:[],1G:q(){7(!6.3d){6.3d=K;7(6.2q){6.F(6.2q,q(){9.O(P)});6.2q=H}7(6.M.3j||6.M.2a)P.43("58",6.1G,N);7(!18.7v.C)6(18).1W(q(){6("#3T").1E()})}}});14 q(){6.F(("7u,7t,1W,7s,7r,3z,5a,7q,"+"7p,7o,7n,3V,59,7m,2y,"+"4k,7l,7k,7j,2c").2R(","),q(i,o){6.11[o]=q(f){v f?9.3g(o,f):9.1t(o)}});7(6.M.3j||6.M.2a)P.46("58",6.1G,N);B 7(6.M.1h){P.7i("<7h"+"7f 2m=3T 7e=K "+"2u=//:><\\/3b>");u a=P.4d("3T");7(a)a.7d=q(){7(9.3a!="1n")v;6.1G()};a=H}B 7(6.M.20)6.3N=3m(q(){7(P.3a=="79"||P.3a=="1n"){3M(6.3N);6.3N=H;6.1G()}},10);6.S.1A(18,"1W",6.1G)};7(6.M.1h)6(18).3Z("3z",q(){u a=6.S.Y;E(u b V a){u c=a[b],i=c.C;7(i&&b!=\'3z\')77 c[i-1]&&6.S.1E(c[i-1],b);1v(--i)}});6.11.1c({76:q(c,b,a){9.1W(c,b,a,1)},1W:q(g,d,c,e){7(6.16(g))v 9.3g("1W",g);c=c||q(){};u f="3K";7(d)7(6.16(d)){c=d;d=H}B{d=6.2E(d);f="50"}u h=9;6.2Z({1C:g,G:f,W:d,2t:e,1n:q(a,b){7(b=="28"||!e&&b=="4V")h.1b("27",a.3c).3J().F(c,[a.3c,b,a]);B c.O(h,[a.3c,b,a])}});v 9},72:q(){v 6.2E(9)},3J:q(){v 9.1L("3b").F(q(){7(9.2u)6.4U(9.2u);B 6.3I(9.2A||9.5H||9.27||"")}).2U()}});6.F("4T,4I,4S,4R,4Q,4P".2R(","),q(i,o){6.11[o]=q(f){v 9.3g(o,f)}});6.1c({1M:q(e,c,a,d,b){7(6.16(c)){a=c;c=H}v 6.2Z({G:"3K",1C:e,W:c,28:a,3G:d,2t:b})},6X:q(d,b,a,c){v 6.1M(d,b,a,c,1)},4U:q(b,a){v 6.1M(b,H,a,"3b")},6V:q(c,b,a){v 6.1M(c,b,a,"4N")},6T:q(d,b,a,c){7(6.16(b)){a=b;b={}}v 6.2Z({G:"50",1C:d,W:b,28:a,3G:c})},6S:q(a){6.36.21=a},6Q:q(a){6.1c(6.36,a)},36:{Y:K,G:"3K",21:0,4O:"6P/x-6O-34-6N",4K:K,38:K,W:H},32:{},2Z:q(s){s=6.1c({},6.36,s);7(s.W){7(s.4K&&1g s.W!="1s")s.W=6.2E(s.W);7(s.G.2H()=="1M"){s.1C+=((s.1C.J("?")>-1)?"&":"?")+s.W;s.W=H}}7(s.Y&&!6.3L++)6.S.1t("4T");u f=N;u h=18.4Z?14 4Z("6L.6J"):14 4J();h.7b(s.G,s.1C,s.38);7(s.W)h.3Q("6H-6G",s.4O);7(s.2t)h.3Q("6F-3O-6D",6.32[s.1C]||"6C, 6B 6A 6z 4r:4r:4r 6y");h.3Q("X-6x-6w","4J");7(s.56)s.56(h);7(s.Y)6.S.1t("4P",[h,s]);u g=q(d){7(h&&(h.3a==4||d=="21")){f=K;7(i){3M(i);i=H}u c;2g{c=6.54(h)&&d!="21"?s.2t&&6.4F(h,s.1C)?"4V":"28":"2c";7(c!="2c"){u b;2g{b=h.3E("53-3O")}25(e){}7(s.2t&&b)6.32[s.1C]=b;u a=6.55(h,s.3G);7(s.28)s.28(a,c);7(s.Y)6.S.1t("4Q",[h,s])}B 6.2X(s,h,c)}25(e){c="2c";6.2X(s,h,c,e)}7(s.Y)6.S.1t("4S",[h,s]);7(s.Y&&!--6.3L)6.S.1t("4I");7(s.1n)s.1n(h,c);7(s.38)h=H}};u i=3m(g,13);7(s.21>0)4C(q(){7(h){h.6r();7(!f)g("21")}},s.21);2g{h.6p(s.W)}25(e){6.2X(s,h,H,e)}7(!s.38)g();v h},2X:q(s,a,b,e){7(s.2c)s.2c(a,b,e);7(s.Y)6.S.1t("4R",[a,s,e])},3L:0,54:q(r){2g{v!r.23&&7A.7B=="4l:"||(r.23>=5u&&r.23<6l)||r.23==5m||6.M.20&&r.23==I}25(e){}v N},4F:q(a,c){2g{u b=a.3E("53-3O");v a.23==5m||b==6.32[c]||6.M.20&&a.23==I}25(e){}v N},55:q(r,b){u c=r.3E("6k-G");u a=!b&&c&&c.J("4B")>=0;a=b=="4B"||a?r.6j:r.3c;7(b=="3b")6.3I(a);7(b=="4N")a=49("("+a+")");7(b=="3F")6("<1x>").3F(a).3J();v a},2E:q(a){u s=[];7(a.15==2b||a.3C)6.F(a,q(){s.R(2l(9.6i)+"="+2l(9.2v))});B E(u j V a)7(a[j]&&a[j].15==2b)6.F(a[j],q(){s.R(2l(j)+"="+2l(9))});B s.R(2l(j)+"="+2l(a[j]));v s.5M("&")},3I:q(a){7(18.4A)18.4A(a);B 7(6.M.20)18.4C(a,0);B 49.3D(18,a)}});6.11.1c({1m:q(b,a){v b?9.1w({1u:"1m",29:"1m",1e:"1m"},b,a):9.1i(":1y").F(q(){9.T.U=9.2i?9.2i:"";7(6.1f(9,"U")=="1P")9.T.U="2h"}).2U()},1j:q(b,a){v b?9.1w({1u:"1j",29:"1j",1e:"1j"},b,a):9.1i(":4f").F(q(){9.2i=9.2i||6.1f(9,"U");7(9.2i=="1P")9.2i="2h";9.T.U="1P"}).2U()},5G:6.11.1R,1R:q(a,b){v 6.16(a)&&6.16(b)?9.5G(a,b):a?9.1w({1u:"1R",29:"1R",1e:"1R"},a,b):9.F(q(){6(9)[6(9).37(":1y")?"1m":"1j"]()})},6e:q(b,a){v 9.1w({1u:"1m"},b,a)},6d:q(b,a){v 9.1w({1u:"1j"},b,a)},6b:q(b,a){v 9.1w({1u:"1R"},b,a)},6a:q(b,a){v 9.1w({1e:"1m"},b,a)},69:q(b,a){v 9.1w({1e:"1j"},b,a)},7U:q(c,a,b){v 9.1w({1e:a},c,b)},1w:q(d,h,f,g){v 9.1l(q(){u c=6(9).37(":1y"),1H=6.5z(h,f,g),5y=9;E(u p V d){7(d[p]=="1j"&&c||d[p]=="1m"&&!c)v 6.16(1H.1n)&&1H.1n.O(9);7(p=="1u"||p=="29"){1H.U=6.1f(9,"U");1H.2f=9.T.2f}}7(1H.2f!=H)9.T.2f="1y";9.2k=6.1c({},d);6.F(d,q(a,b){u e=14 6.2M(5y,1H,a);7(b.15==3y)e.2W(e.1K(),b);B e[b=="1R"?c?"1m":"1j":b](d)})})},1l:q(a,b){7(!b){b=a;a="2M"}v 9.F(q(){7(!9.1l)9.1l={};7(!9.1l[a])9.1l[a]=[];9.1l[a].R(b);7(9.1l[a].C==1)b.O(9)})}});6.1c({5z:q(b,a,c){u d=b&&b.15==64?b:{1n:c||!c&&a||6.16(b)&&b,1B:b,2I:c&&a||a&&a.15!=45&&a||(6.2I.4i?"4i":"4w")};d.1B=(d.1B&&d.1B.15==3y?d.1B:{61:60,89:5u}[d.1B])||8a;d.2N=d.1n;d.1n=q(){6.5I(9,"2M");7(6.16(d.2N))d.2N.O(9)};v d},2I:{4w:q(p,n,b,a){v b+a*p},4i:q(p,n,b,a){v((-5W.5X(p*5W.8e)/2)+0.5)*a+b}},1l:{},5I:q(b,a){a=a||"2M";7(b.1l&&b.1l[a]){b.1l[a].4e();u f=b.1l[a][0];7(f)f.O(b)}},3B:[],2M:q(f,e,g){u z=9;u y=f.T;z.a=q(){7(e.3A)e.3A.O(f,[z.2o]);7(g=="1e")6.1b(y,"1e",z.2o);B{y[g]=8m(z.2o)+"4o";y.U="2h"}};z.5V=q(){v 39(6.1f(f,g))};z.1K=q(){u r=39(6.2z(f,g));v r&&r>-8l?r:z.5V()};z.2W=q(c,b){z.4s=(14 5T()).5S();z.2o=c;z.a();6.3B.R(q(){v z.3A(c,b)});7(6.3B.C==1){u d=3m(q(){u a=6.3B;E(u i=0;i<a.C;i++)7(!a[i]())a.8j(i--,1);7(!a.C)3M(d)},13)}};z.1m=q(){7(!f.24)f.24={};f.24[g]=6.1b(f.T,g);e.1m=K;z.2W(0,9.1K());7(g!="1e")y[g]="8q";6(f).1m()};z.1j=q(){7(!f.24)f.24={};f.24[g]=6.1b(f.T,g);e.1j=K;z.2W(9.1K(),0)};z.3A=q(a,c){u t=(14 5T()).5S();7(t>e.1B+z.4s){z.2o=c;z.a();7(f.2k)f.2k[g]=K;u b=K;E(u i V f.2k)7(f.2k[i]!==K)b=N;7(b){7(e.U!=H){y.2f=e.2f;y.U=e.U;7(6.1f(f,"U")=="1P")y.U="2h"}7(e.1j)y.U="1P";7(e.1j||e.1m)E(u p V f.2k)6.1b(y,p,f.24[p])}7(b&&6.16(e.1n))e.1n.O(f);v N}B{u n=t-9.4s;u p=n/e.1B;z.2o=6.2I[e.2I](p,n,a,(c-a),e.1B);z.a()}v K}}})}',62,524,'||||||jQuery|if||this|||||||||||||||||function||||var|return||||||else|length||for|each|type|null|undefined|indexOf|true|parentNode|browser|false|apply|document|nodeName|push|event|style|display|in|data||global|||fn|className||new|constructor|isFunction|test|window|arguments|events|attr|extend|firstChild|opacity|css|typeof|msie|filter|hide|mergeNum|queue|show|complete|replace|handle|nodeType|table|string|trigger|height|while|animate|div|hidden|tbody|add|duration|url|toUpperCase|remove|break|ready|opt|_|button|cur|find|get|tb|target|none|guid|toggle|args|merge|styleFloat|exec|load|nextSibling|ret|pushStack|safari|timeout|nth|status|orig|catch|al|innerHTML|success|width|opera|Array|error|preventDefault|rl|overflow|try|block|oldblock|done|curAnim|encodeURIComponent|id||now|index|readyList|disabled|grep|ifModified|src|value|inArray|multiFilter|select|curCSS|text|checked|trim|stopPropagation|param|domManip|substr|toLowerCase|easing|chars|insertBefore|makeArray|fx|old|ownerDocument|last|first|split|childNodes|selected|end|tr|custom|handleError|empty|ajax|el|clean|lastModified|String|form|getAttribute|ajaxSettings|is|async|parseFloat|readyState|script|responseText|isReady|append|defaultView|bind|which|position|mozilla|map|delete|setInterval|static|RegExp|oWidth|removeChild|oHeight|cloneNode|match|child|toString|has|float|Number|unload|step|timers|jquery|call|getResponseHeader|html|dataType|props|globalEval|evalScripts|GET|active|clearInterval|safariTimer|Modified|num|setRequestHeader|getElementsByTagName|currentStyle|__ie_init|unbind|mouseover|handleHover|init|getComputedStyle|one|isXMLDoc|relatedTarget|fix|removeEventListener|handler|Function|addEventListener|triggered|visibility|eval|nodeIndex|radio|classFilter|getElementById|shift|visible|appendChild|documentElement|swing|fromElement|submit|file|swap|expr|px|parents|sibling|00|startTime|previousSibling|lastToggle|parent|linear|ol|body|tagName|execScript|xml|setTimeout|version|setArray|httpNotModified|fl|prop|ajaxStop|XMLHttpRequest|processData|alpha|href|json|contentType|ajaxSend|ajaxSuccess|ajaxError|ajaxComplete|ajaxStart|getScript|notmodified|colgroup|100|not|ActiveXObject|POST|slice|fieldset|Last|httpSuccess|httpData|beforeSend|getPropertyValue|DOMContentLoaded|mouseout|click|ctrlKey|metaKey|keyCode|charCode|scrollTop|unique|createElement|scrollLeft|clientX|pageX|webkit|304|srcElement|appendTo|unshift|prevObject|on|after|before|200|removeAttr|prepend|cssFloat|self|speed|parse|input|reset|image|password|checkbox|_toggle|textContent|dequeue|lastChild|odd|even|join|contains|gt|lt|eq|nodeValue|getTime|Date|zoom|max|Math|cos|font|maxLength|600|slow|maxlength|readOnly|Object|readonly|createTextNode|class|htmlFor|fadeOut|fadeIn|slideToggle|CSS1Compat|slideUp|slideDown|compatMode|boxModel|compatible|name|responseXML|content|300|ie|noConflict|ra|send|it|abort|rv|userAgent|navigator|concat|With|Requested|GMT|1970|Jan|01|Thu|Since|reverse|If|Type|Content|array|XMLHTTP|ig|Microsoft|NaN|urlencoded|www|application|ajaxSetup|val|ajaxTimeout|post|setAttribute|getJSON|getAttributeNode|getIfModified|method|FORM|action|options|serialize|col|th|td|loadIfModified|do|colg|loaded|tfoot|open|thead|onreadystatechange|defer|ipt|leg|scr|write|keyup|keypress|keydown|change|mousemove|mouseup|mousedown|dblclick|scroll|resize|focus|blur|frames|hover|clone|clientY|pageY|location|protocol|toElement|clientWidth|clientHeight|cancelBubble|relative|returnValue|left|detachEvent|right|absolute|attachEvent|substring|offsetWidth|object|offsetHeight|continue|Width|border|fadeTo|padding|size|uFFFF|Left|u0128|Right|Bottom|textarea|Top|enabled|innerText|only|toggleClass|removeClass|fast|400|wrap|addClass|removeAttribute|PI|insertAfter|prependTo|children|line|splice|siblings|10000|parseInt|prev|next|weight|1px|prototype'.split('|'),0,{}))

/* json.js */





SimileAjax.JSON=new Object();

(function(){
var m={
'\b':'\\b',
'\t':'\\t',
'\n':'\\n',
'\f':'\\f',
'\r':'\\r',
'"':'\\"',
'\\':'\\\\'
};
var s={
array:function(x){
var a=['['],b,f,i,l=x.length,v;
for(i=0;i<l;i+=1){
v=x[i];
f=s[typeof v];
if(f){
v=f(v);
if(typeof v=='string'){
if(b){
a[a.length]=',';
}
a[a.length]=v;
b=true;
}
}
}
a[a.length]=']';
return a.join('');
},
'boolean':function(x){
return String(x);
},
'null':function(x){
return"null";
},
number:function(x){
return isFinite(x)?String(x):'null';
},
object:function(x){
if(x){
if(x instanceof Array){
return s.array(x);
}
var a=['{'],b,f,i,v;
for(i in x){
v=x[i];
f=s[typeof v];
if(f){
v=f(v);
if(typeof v=='string'){
if(b){
a[a.length]=',';
}
a.push(s.string(i),':',v);
b=true;
}
}
}
a[a.length]='}';
return a.join('');
}
return'null';
},
string:function(x){
if(/["\\\x00-\x1f]/.test(x)){
x=x.replace(/([\x00-\x1f\\"])/g,function(a,b){
var c=m[b];
if(c){
return c;
}
c=b.charCodeAt();
return'\\u00'+
Math.floor(c/16).toString(16)+
(c%16).toString(16);
});
}
return'"'+x+'"';
}
};

SimileAjax.JSON.toJSONString=function(o){
if(o instanceof Object){
return s.object(o);
}else if(o instanceof Array){
return s.array(o);
}else{
return o.toString();
}
};

SimileAjax.JSON.parseJSON=function(){
try{
return!(/[^,:{}\[\]0-9.\-+Eaeflnr-u \n\r\t]/.test(
this.replace(/"(\\.|[^"\\])*"/g,'')))&&
eval('('+this+')');
}catch(e){
return false;
}
};
})();


/* string.js */



String.prototype.trim=function(){
return this.replace(/^\s+|\s+$/g,'');
};

String.prototype.startsWith=function(prefix){
return this.length>=prefix.length&&this.substr(0,prefix.length)==prefix;
};

String.prototype.endsWith=function(suffix){
return this.length>=suffix.length&&this.substr(this.length-suffix.length)==suffix;
};

String.substitute=function(s,objects){
var result="";
var start=0;
while(start<s.length-1){
var percent=s.indexOf("%",start);
if(percent<0||percent==s.length-1){
break;
}else if(percent>start&&s.charAt(percent-1)=="\\"){
result+=s.substring(start,percent-1)+"%";
start=percent+1;
}else{
var n=parseInt(s.charAt(percent+1));
if(isNaN(n)||n>=objects.length){
result+=s.substring(start,percent+2);
}else{
result+=s.substring(start,percent)+objects[n].toString();
}
start=percent+2;
}
}

if(start<s.length){
result+=s.substring(start);
}
return result;
};


/* units.js */





SimileAjax.NativeDateUnit=new Object();



SimileAjax.NativeDateUnit.makeDefaultValue=function(){

return new Date();

};



SimileAjax.NativeDateUnit.cloneValue=function(v){

return new Date(v.getTime());

};



SimileAjax.NativeDateUnit.getParser=function(format){

if(typeof format=="string"){

format=format.toLowerCase();

}

return(format=="iso8601"||format=="iso 8601")?

SimileAjax.DateTime.parseIso8601DateTime:

SimileAjax.DateTime.parseGregorianDateTime;

};



SimileAjax.NativeDateUnit.parseFromObject=function(o){

return SimileAjax.DateTime.parseGregorianDateTime(o);

};



SimileAjax.NativeDateUnit.toNumber=function(v){

return v.getTime();

};



SimileAjax.NativeDateUnit.fromNumber=function(n){

return new Date(n);

};



SimileAjax.NativeDateUnit.compare=function(v1,v2){

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



SimileAjax.NativeDateUnit.earlier=function(v1,v2){

return SimileAjax.NativeDateUnit.compare(v1,v2)<0?v1:v2;

};



SimileAjax.NativeDateUnit.later=function(v1,v2){

return SimileAjax.NativeDateUnit.compare(v1,v2)>0?v1:v2;

};



SimileAjax.NativeDateUnit.change=function(v,n){

return new Date(v.getTime()+n);

};





/* window-manager.js */




SimileAjax.WindowManager={
_initialized:false,
_listeners:[],

_draggedElement:null,
_draggedElementCallback:null,
_dropTargetHighlightElement:null,
_lastCoords:null,
_ghostCoords:null,
_draggingMode:"",
_dragging:false,

_layers:[]
};

SimileAjax.WindowManager.initialize=function(){
if(SimileAjax.WindowManager._initialized){
return;
}

SimileAjax.DOM.registerEvent(document.body,"mousedown",SimileAjax.WindowManager._onBodyMouseDown);
SimileAjax.DOM.registerEvent(document.body,"mousemove",SimileAjax.WindowManager._onBodyMouseMove);
SimileAjax.DOM.registerEvent(document.body,"mouseup",SimileAjax.WindowManager._onBodyMouseUp);
SimileAjax.DOM.registerEvent(document,"keydown",SimileAjax.WindowManager._onBodyKeyDown);
SimileAjax.DOM.registerEvent(document,"keyup",SimileAjax.WindowManager._onBodyKeyUp);

SimileAjax.WindowManager._layers.push({index:0});

SimileAjax.WindowManager._historyListener={
onBeforeUndoSeveral:function(){},
onAfterUndoSeveral:function(){},
onBeforeUndo:function(){},
onAfterUndo:function(){},

onBeforeRedoSeveral:function(){},
onAfterRedoSeveral:function(){},
onBeforeRedo:function(){},
onAfterRedo:function(){}
};
SimileAjax.History.addListener(SimileAjax.WindowManager._historyListener);

SimileAjax.WindowManager._initialized=true;
};

SimileAjax.WindowManager.getBaseLayer=function(){
SimileAjax.WindowManager.initialize();
return SimileAjax.WindowManager._layers[0];
};

SimileAjax.WindowManager.getHighestLayer=function(){
SimileAjax.WindowManager.initialize();
return SimileAjax.WindowManager._layers[SimileAjax.WindowManager._layers.length-1];
};

SimileAjax.WindowManager.registerEventWithObject=function(elmt,eventName,obj,handlerName,layer){
SimileAjax.WindowManager.registerEvent(
elmt,
eventName,
function(elmt2,evt,target){
return obj[handlerName].call(obj,elmt2,evt,target);
},
layer
);
};

SimileAjax.WindowManager.registerEvent=function(elmt,eventName,handler,layer){
if(layer==null){
layer=SimileAjax.WindowManager.getHighestLayer();
}

var handler2=function(elmt,evt,target){
if(SimileAjax.WindowManager._canProcessEventAtLayer(layer)){
SimileAjax.WindowManager._popToLayer(layer.index);
try{
handler(elmt,evt,target);
}catch(e){
SimileAjax.Debug.exception(e);
}
}
SimileAjax.DOM.cancelEvent(evt);
return false;
}

SimileAjax.DOM.registerEvent(elmt,eventName,handler2);
};

SimileAjax.WindowManager.pushLayer=function(f,ephemeral,elmt){
var layer={onPop:f,index:SimileAjax.WindowManager._layers.length,ephemeral:(ephemeral),elmt:elmt};
SimileAjax.WindowManager._layers.push(layer);

return layer;
};

SimileAjax.WindowManager.popLayer=function(layer){
for(var i=1;i<SimileAjax.WindowManager._layers.length;i++){
if(SimileAjax.WindowManager._layers[i]==layer){
SimileAjax.WindowManager._popToLayer(i-1);
break;
}
}
};

SimileAjax.WindowManager.popAllLayers=function(){
SimileAjax.WindowManager._popToLayer(0);
};

SimileAjax.WindowManager.registerForDragging=function(elmt,callback,layer){
SimileAjax.WindowManager.registerEvent(
elmt,
"mousedown",
function(elmt,evt,target){
SimileAjax.WindowManager._handleMouseDown(elmt,evt,callback);
},
layer
);
};

SimileAjax.WindowManager._popToLayer=function(level){
while(level+1<SimileAjax.WindowManager._layers.length){
try{
var layer=SimileAjax.WindowManager._layers.pop();
if(layer.onPop!=null){
layer.onPop();
}
}catch(e){
}
}
};

SimileAjax.WindowManager._canProcessEventAtLayer=function(layer){
if(layer.index==(SimileAjax.WindowManager._layers.length-1)){
return true;
}
for(var i=layer.index+1;i<SimileAjax.WindowManager._layers.length;i++){
if(!SimileAjax.WindowManager._layers[i].ephemeral){
return false;
}
}
return true;
};

SimileAjax.WindowManager.cancelPopups=function(evt){
var evtCoords=(evt)?SimileAjax.DOM.getEventPageCoordinates(evt):{x:-1,y:-1};

var i=SimileAjax.WindowManager._layers.length-1;
while(i>0&&SimileAjax.WindowManager._layers[i].ephemeral){
var layer=SimileAjax.WindowManager._layers[i];
if(layer.elmt!=null){
var elmt=layer.elmt;
var elmtCoords=SimileAjax.DOM.getPageCoordinates(elmt);
if(evtCoords.x>=elmtCoords.left&&evtCoords.x<(elmtCoords.left+elmt.offsetWidth)&&
evtCoords.y>=elmtCoords.top&&evtCoords.y<(elmtCoords.top+elmt.offsetHeight)){
break;
}
}
i--;
}
SimileAjax.WindowManager._popToLayer(i);
};

SimileAjax.WindowManager._onBodyMouseDown=function(elmt,evt,target){
if(!("eventPhase"in evt)||evt.eventPhase==evt.BUBBLING_PHASE){
SimileAjax.WindowManager.cancelPopups(evt);
}
};

SimileAjax.WindowManager._handleMouseDown=function(elmt,evt,callback){
SimileAjax.WindowManager._draggedElement=elmt;
SimileAjax.WindowManager._draggedElementCallback=callback;
SimileAjax.WindowManager._lastCoords={x:evt.clientX,y:evt.clientY};

SimileAjax.DOM.cancelEvent(evt);
return false;
};

SimileAjax.WindowManager._onBodyKeyDown=function(elmt,evt,target){
if(SimileAjax.WindowManager._dragging){
if(evt.keyCode==27){
SimileAjax.WindowManager._cancelDragging();
}else if((evt.keyCode==17||evt.keyCode==16)&&SimileAjax.WindowManager._draggingMode!="copy"){
SimileAjax.WindowManager._draggingMode="copy";

var img=SimileAjax.Graphics.createTranslucentImage(SimileAjax.urlPrefix+"images/copy.png");
img.style.position="absolute";
img.style.left=(SimileAjax.WindowManager._ghostCoords.left-16)+"px";
img.style.top=(SimileAjax.WindowManager._ghostCoords.top)+"px";
document.body.appendChild(img);

SimileAjax.WindowManager._draggingModeIndicatorElmt=img;
}
}
};

SimileAjax.WindowManager._onBodyKeyUp=function(elmt,evt,target){
if(SimileAjax.WindowManager._dragging){
if(evt.keyCode==17||evt.keyCode==16){
SimileAjax.WindowManager._draggingMode="";
if(SimileAjax.WindowManager._draggingModeIndicatorElmt!=null){
document.body.removeChild(SimileAjax.WindowManager._draggingModeIndicatorElmt);
SimileAjax.WindowManager._draggingModeIndicatorElmt=null;
}
}
}
};

SimileAjax.WindowManager._onBodyMouseMove=function(elmt,evt,target){
if(SimileAjax.WindowManager._draggedElement!=null){
var callback=SimileAjax.WindowManager._draggedElementCallback;

var lastCoords=SimileAjax.WindowManager._lastCoords;
var diffX=evt.clientX-lastCoords.x;
var diffY=evt.clientY-lastCoords.y;

if(!SimileAjax.WindowManager._dragging){
if(Math.abs(diffX)>5||Math.abs(diffY)>5){
try{
if("onDragStart"in callback){
callback.onDragStart();
}

if("ghost"in callback&&callback.ghost){
var draggedElmt=SimileAjax.WindowManager._draggedElement;

SimileAjax.WindowManager._ghostCoords=SimileAjax.DOM.getPageCoordinates(draggedElmt);
SimileAjax.WindowManager._ghostCoords.left+=diffX;
SimileAjax.WindowManager._ghostCoords.top+=diffY;

var ghostElmt=draggedElmt.cloneNode(true);
ghostElmt.style.position="absolute";
ghostElmt.style.left=SimileAjax.WindowManager._ghostCoords.left+"px";
ghostElmt.style.top=SimileAjax.WindowManager._ghostCoords.top+"px";
ghostElmt.style.zIndex=1000;
SimileAjax.Graphics.setOpacity(ghostElmt,50);

document.body.appendChild(ghostElmt);
callback._ghostElmt=ghostElmt;
}

SimileAjax.WindowManager._dragging=true;
SimileAjax.WindowManager._lastCoords={x:evt.clientX,y:evt.clientY};

document.body.focus();
}catch(e){
SimileAjax.Debug.exception("WindowManager: Error handling mouse down",e);
SimileAjax.WindowManager._cancelDragging();
}
}
}else{
try{
SimileAjax.WindowManager._lastCoords={x:evt.clientX,y:evt.clientY};

if("onDragBy"in callback){
callback.onDragBy(diffX,diffY);
}

if("_ghostElmt"in callback){
var ghostElmt=callback._ghostElmt;

SimileAjax.WindowManager._ghostCoords.left+=diffX;
SimileAjax.WindowManager._ghostCoords.top+=diffY;

ghostElmt.style.left=SimileAjax.WindowManager._ghostCoords.left+"px";
ghostElmt.style.top=SimileAjax.WindowManager._ghostCoords.top+"px";
if(SimileAjax.WindowManager._draggingModeIndicatorElmt!=null){
var indicatorElmt=SimileAjax.WindowManager._draggingModeIndicatorElmt;

indicatorElmt.style.left=(SimileAjax.WindowManager._ghostCoords.left-16)+"px";
indicatorElmt.style.top=SimileAjax.WindowManager._ghostCoords.top+"px";
}

if("droppable"in callback&&callback.droppable){
var coords=SimileAjax.DOM.getEventPageCoordinates(evt);
var target=SimileAjax.DOM.hittest(
coords.x,coords.y,
[SimileAjax.WindowManager._ghostElmt,
SimileAjax.WindowManager._dropTargetHighlightElement
]
);
target=SimileAjax.WindowManager._findDropTarget(target);

if(target!=SimileAjax.WindowManager._potentialDropTarget){
if(SimileAjax.WindowManager._dropTargetHighlightElement!=null){
document.body.removeChild(SimileAjax.WindowManager._dropTargetHighlightElement);

SimileAjax.WindowManager._dropTargetHighlightElement=null;
SimileAjax.WindowManager._potentialDropTarget=null;
}

var droppable=false;
if(target!=null){
if((!("canDropOn"in callback)||callback.canDropOn(target))&&
(!("canDrop"in target)||target.canDrop(SimileAjax.WindowManager._draggedElement))){

droppable=true;
}
}

if(droppable){
var border=4;
var targetCoords=SimileAjax.DOM.getPageCoordinates(target);
var highlight=document.createElement("div");
highlight.style.border=border+"px solid yellow";
highlight.style.backgroundColor="yellow";
highlight.style.position="absolute";
highlight.style.left=targetCoords.left+"px";
highlight.style.top=targetCoords.top+"px";
highlight.style.width=(target.offsetWidth-border*2)+"px";
highlight.style.height=(target.offsetHeight-border*2)+"px";
SimileAjax.Graphics.setOpacity(highlight,30);
document.body.appendChild(highlight);

SimileAjax.WindowManager._potentialDropTarget=target;
SimileAjax.WindowManager._dropTargetHighlightElement=highlight;
}
}
}
}
}catch(e){
SimileAjax.Debug.exception("WindowManager: Error handling mouse move",e);
SimileAjax.WindowManager._cancelDragging();
}
}

SimileAjax.DOM.cancelEvent(evt);
return false;
}
};

SimileAjax.WindowManager._onBodyMouseUp=function(elmt,evt,target){
if(SimileAjax.WindowManager._draggedElement!=null){
try{
if(SimileAjax.WindowManager._dragging){
var callback=SimileAjax.WindowManager._draggedElementCallback;
if("onDragEnd"in callback){
callback.onDragEnd();
}
if("droppable"in callback&&callback.droppable){
var dropped=false;

var target=SimileAjax.WindowManager._potentialDropTarget;
if(target!=null){
if((!("canDropOn"in callback)||callback.canDropOn(target))&&
(!("canDrop"in target)||target.canDrop(SimileAjax.WindowManager._draggedElement))){

if("onDropOn"in callback){
callback.onDropOn(target);
}
target.ondrop(SimileAjax.WindowManager._draggedElement,SimileAjax.WindowManager._draggingMode);

dropped=true;
}
}

if(!dropped){

}
}
}
}finally{
SimileAjax.WindowManager._cancelDragging();
}

SimileAjax.DOM.cancelEvent(evt);
return false;
}
};

SimileAjax.WindowManager._cancelDragging=function(){
var callback=SimileAjax.WindowManager._draggedElementCallback;
if("_ghostElmt"in callback){
var ghostElmt=callback._ghostElmt;
document.body.removeChild(ghostElmt);

delete callback._ghostElmt;
}
if(SimileAjax.WindowManager._dropTargetHighlightElement!=null){
document.body.removeChild(SimileAjax.WindowManager._dropTargetHighlightElement);
SimileAjax.WindowManager._dropTargetHighlightElement=null;
}
if(SimileAjax.WindowManager._draggingModeIndicatorElmt!=null){
document.body.removeChild(SimileAjax.WindowManager._draggingModeIndicatorElmt);
SimileAjax.WindowManager._draggingModeIndicatorElmt=null;
}

SimileAjax.WindowManager._draggedElement=null;
SimileAjax.WindowManager._draggedElementCallback=null;
SimileAjax.WindowManager._potentialDropTarget=null;
SimileAjax.WindowManager._dropTargetHighlightElement=null;
SimileAjax.WindowManager._lastCoords=null;
SimileAjax.WindowManager._ghostCoords=null;
SimileAjax.WindowManager._draggingMode="";
SimileAjax.WindowManager._dragging=false;
};

SimileAjax.WindowManager._findDropTarget=function(elmt){
while(elmt!=null){
if("ondrop"in elmt&&(typeof elmt.ondrop)=="function"){
break;
}
elmt=elmt.parentNode;
}
return elmt;
};


/* xmlhttp.js */



SimileAjax.XmlHttp=new Object();


SimileAjax.XmlHttp._onReadyStateChange=function(xmlhttp,fError,fDone){
switch(xmlhttp.readyState){





case 4:
try{
if(xmlhttp.status==0
||xmlhttp.status==200
){
if(fDone){
fDone(xmlhttp);
}
}else{
if(fError){
fError(
xmlhttp.statusText,
xmlhttp.status,
xmlhttp
);
}
}
}catch(e){
SimileAjax.Debug.exception("XmlHttp: Error handling onReadyStateChange",e);
}
break;
}
};


SimileAjax.XmlHttp._createRequest=function(){
if(SimileAjax.Platform.browser.isIE){
var programIDs=[
"Msxml2.XMLHTTP",
"Microsoft.XMLHTTP",
"Msxml2.XMLHTTP.4.0"
];
for(var i=0;i<programIDs.length;i++){
try{
var programID=programIDs[i];
var f=function(){
return new ActiveXObject(programID);
};
var o=f();






SimileAjax.XmlHttp._createRequest=f;

return o;
}catch(e){

}
}

}

try{
var f=function(){
return new XMLHttpRequest();
};
var o=f();






SimileAjax.XmlHttp._createRequest=f;

return o;
}catch(e){
throw new Error("Failed to create an XMLHttpRequest object");
}
};


SimileAjax.XmlHttp.get=function(url,fError,fDone){
var xmlhttp=SimileAjax.XmlHttp._createRequest();

xmlhttp.open("GET",url,true);
xmlhttp.onreadystatechange=function(){
SimileAjax.XmlHttp._onReadyStateChange(xmlhttp,fError,fDone);
};
xmlhttp.send(null);
};


SimileAjax.XmlHttp.post=function(url,body,fError,fDone){
var xmlhttp=SimileAjax.XmlHttp._createRequest();

xmlhttp.open("POST",url,true);
xmlhttp.onreadystatechange=function(){
SimileAjax.XmlHttp._onReadyStateChange(xmlhttp,fError,fDone);
};
xmlhttp.send(body);
};

SimileAjax.XmlHttp._forceXML=function(xmlhttp){
try{
xmlhttp.overrideMimeType("text/xml");
}catch(e){
xmlhttp.setrequestheader("Content-Type","text/xml");
}
};