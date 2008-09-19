// TODO: Get some opts from cookies?

var isNull = MochiKit.Base.isUndefinedOrNull;

var defOptions = {
        "resolution":   5,
        "npoints":   5,
        "fakeServiceMode": 0
    };

function Speed(options){

    // Provide defaults
    this.options = {
        // required args:
        // "canvas"

        // defaults
        "maxValue": 10000,
        "numBars": 70,              // how many bars
        "percentBar": 0.6,          // how much of each 'bar' is lit
        "emptyAlpha": 0.3,          // how much to obscure colors

        "staleAlpha": 0.4,          // how much to obscure colors
        "staleWidth": 0.75,         // how much to obscure colors

        "jitterPercent":    0.001,  // bounce a bit around value :)

        "dataPeriod":       5,      // seconds - how often to poll pS

        "refreshPeriod":    0.100,  // seconds - how often to update screen
        "minDataPeriod":    2,      // seconds - min duration to show one value
        "dataStalePeriod":  15,     // seconds - when to show 'inactive'

        "useMaxValueSmoothing":   true,
        "maxValueSmoothingHistory":   4,

        "splabelName":  "speedo-value",
        "sptimeName":  "speedo-time",
        "spdateName":  "speedo-date",
        "doIntro":  false
    };

    for(var p in options){
        log("options[",p,"]: ",options[p]);
        this.options[p] = options[p];
    }

    if(!this.options.canvas){
        throw new Error("Speed: \"canvas\" property required");
    }
    this.canvas = this.options.canvas;
    this.ctx = this.canvas.getContext("2d");

    /*
     * Options sanity checks
     */
    if(this.options.maxValue <= 0){
        throw new Error("Speed: \"maxValue\" must be > 0");
    }

    if(this.options.dataStalePeriod <= 0){
        throw new Error("Speed: \"dataStalePeriod\" must be > 0");
    }
    if(this.options.minDataPeriod <= 0){
        throw new Error("Speed: \"minDataPeriod\" must be > 0");
    }
    if(this.options.dataStalePeriod <= 0){
        throw new Error("Speed: \"dataStalePeriod\" must be > 0");
    }

    if(this.options.dataStalePeriod < this.options.minDataPeriod){
        throw new Error("Speed: \"minDataPeriod\" must be < \"dataStalePeriod\"");
    }
    if(this.options.minDataPeriod < this.options.refreshPeriod){
        throw new Error("Speed: \"refreshPeriod\" must be < \"minDataPeriod\"");
    }

    // convert to milli for js event requests
    this.refreshPeriod = this.options.refreshPeriod * 1000;

    // Determine number of refresh 'steps' before a new datavalue can be shown
    this.minRefreshSteps = this.options.minDataPeriod /
                                        this.options.refreshPeriod;
    // Determine number of refresh 'steps' before data is stale
    this.maxRefreshSteps = this.options.dataStalePeriod /
                                        this.options.refreshPeriod;
    
    // keep track of the number of refreshes between data value changes
    this.stale = true;
    this.steps = 0;
    this.currentValue = this.nextValue = 0;
    this.currentDate = this.nextDate = new Date(0);
    this.maxHistoryValues = [];

    this.hc = this.canvas.height;
    this.wc = this.canvas.width;

    // fillstyle for drawing 'empty' bar
    var estyle = this.ctx.createLinearGradient(0,this.hc,0,0);

    estyle.addColorStop(0.0,"rgba(0,255,0," + this.options.emptyAlpha + ")");
    estyle.addColorStop(0.1,"rgba(0,255,0," + this.options.emptyAlpha + ")");

    estyle.addColorStop(0.45,"rgba(255,255,0," + this.options.emptyAlpha + ")");
    estyle.addColorStop(0.55,"rgba(255,255,0," + this.options.emptyAlpha + ")");

    estyle.addColorStop(0.9,"rgba(255,0,0," + this.options.emptyAlpha + ")");
    estyle.addColorStop(1.0,"rgba(255,0,0," + this.options.emptyAlpha + ")");

    // fillstyle for drawing 'full' bar
    var fstyle = this.ctx.createLinearGradient(0,this.hc,0,0);

    fstyle.addColorStop(0.0,"rgba(0,255,0,1)");
    fstyle.addColorStop(0.1,"rgba(0,255,0,1)");

    fstyle.addColorStop(0.45,"rgba(255,255,0,1)");
    fstyle.addColorStop(0.55,"rgba(255,255,0,1)");

    fstyle.addColorStop(0.9,"rgba(255,0,0,1)");
    fstyle.addColorStop(1.0,"rgba(255,0,0,1)");

    this.estyle = estyle;
    this.fstyle = fstyle;

    // this.initCanvas();

    if(this.options.splabelName){
        this.splabel = $(this.options.splabelName);
        if(this.splabel.tagName != "P"){
            throw new Error("Speed: splabelName should indicate \'P\' element");
        }
    }

    if(this.options.sptimeName){
        this.sptime = $(this.options.sptimeName);
        if(this.sptime.tagName != "P"){
            throw new Error("Speed: sptimeName should indicate \'P\' element");
        }
    }

    if(this.options.spdateName){
        this.spdate = $(this.options.spdateName);
        if(this.spdate.tagName != "P"){
            throw new Error("Speed: spdateName should indicate \'P\' element");
        }
    }

    if(this.options.doIntro){
        this.intro();
    }

    return this;
}

Speed.prototype.appendData = function(a){

    if(arguments.length != 1){
        throw new Error("Speed.appendData(): Only one arg allowed");
    }

    // normalize input arg
    var arr;
    if(typeof(a) != "number"){
        if(!a.length) return;
        arr = a;
    }
    else{
        arr = [a];
    }

    // make sure data is initalized
    if(!this.data){
        this.data = [];
    }

    // If arr elements are arrays - then only 'new' elements should be
    // added. (key is the first element of the interior array, value
    // is the second element.) Array must already be sorted. This
    // is a very dumb algorithm...
    if(arr[0].length){


        if(!this.lastKey) this.lastKey = 0;

        // remove duplicate/old elements
        while(arr.length && (arr[0][0] <= this.lastKey)){
            arr.shift();
        }

        if(arr.length){
            this.lastKey = arr[arr.length-1][0];
        }
    }

    log("appendData: speedo data has ",this.data.length);
//    if(this.data.length > 0){
//        if(this.data[this.data.length-1].length){
//            log("lastdata: [",this.data[this.data.length-1][0],"][",this.data[this.data.length-1][1].toPrecision(9),"]");
//        }
//    }

    log("appendData: adding ",arr.length);
    if(!arr.length) return;
    if(arr[0].length){
        for(var i=0; i< arr.length; i++){
            log("adding: [",arr[i][0],"][",arr[i][1].toPrecision(9),"]");
        }
    }
    this.data = this.data.concat(arr);
    log("appendData: data updated to ",this.data.length);

    // Now start refreshing the display!
    if(!this.interval){
        this.interval = setInterval(MochiKit.Base.bind(this.refresh,this),
                this.refreshPeriod);
    }

    return;
}

Speed.prototype.intro = function(){
    var a = [0,
        //        this.options.maxValue*.5,
        this.options.maxValue,
        0,
        //        this.options.maxValue*.5,
        this.options.maxValue,
        //        this.options.maxValue*.5,
        ];

    this.appendData(a);

    return;
}

Speed.prototype.refresh = function(){
    // fetch data from beginning of this.data array
    var newValue;
    var newDate;

    this.steps++;

    if(!this.stale && (this.steps < this.minRefreshSteps)){
        // take one more step toward the 'next' value.

        var valDiff = this.nextValue - this.currentValue;
        if(valDiff){
            newValue = this.currentValue +
                                (valDiff * this.steps / this.minRefreshSteps);
        }
        else{
            newValue = this.currentValue;
        }

        newDate = this.currentDate;

    }
    else{
        // Time to update to a new data value

        if(this.data && this.data.length){
            var nDate;
            var nTime;
            var nextTime;

            // new data value - reset steps
            this.steps = 0;
            this.stale = false;

            // update currentValue and nextValue
            this.currentValue = this.nextValue;
            this.currentDate = this.nextDate;

            // update nextValue
            var nextValue = this.data.shift();

            if(nextValue.length > 1){
                this.nextDate = new Date(nextValue[0] * 1000);
                nextValue = nextValue[1];
            }
            else{
                this.nextDate = new Date();
            }

            // maxValue smoothing for 'nextValue'
            if(this.options.useMaxValueSmoothing){
                this.maxHistoryValues.push(nextValue);
                if(this.maxHistoryValues.length >
                                        this.options.maxValueSmoothingHistory){
                    this.maxHistoryValues.shift();
                }
                this.nextValue = Math.max.apply(null,this.maxHistoryValues);
            }
            else{
                this.nextValue = nextValue;
            }
            newValue = this.currentValue;
            newDate = this.currentDate;
        }
        else{
            if(this.steps > this.maxRefreshSteps){
                this.stale = true;
                if(this.interval){
                    clearInterval(this.interval);
                    delete this.interval;
                }
            }
            newValue = this.nextValue;
            newDate = this.nextDate;
        }
    }

    var randValue = newValue;
    if(!this.stale){
        // random jitter for target
        var reach = this.options.maxValue * this.options.jitterPercent;
        randValue = (newValue - reach) + (2 * reach * Math.random());
    }

    if(randValue < 0) randValue = 0;
    if(randValue > this.options.maxValue) randValue = this.options.maxValue;

    var nBars = this.options.numBars -
                    (this.options.numBars * randValue/this.options.maxValue);
    var hb = this.hc/this.options.numBars;
    var hl = hb * this.options.percentBar;
    var w = this.wc;

    this.ctx.save();
    this.ctx.clearRect(
            0,0,
            w,this.hc);
    if(this.stale){
        this.ctx.translate(this.wc*(1-this.options.staleWidth)*.5,0);
        w *= this.options.staleWidth;
    }

    // empty portion
    this.ctx.fillStyle = this.estyle;
    this.ctx.beginPath();
    for(var i=0; i < nBars; i++){
        this.ctx.rect(0,(hb*i)+(.5*hl),w,hl);
    }
    this.ctx.closePath();
    this.ctx.fill();

    // full portion
    if(nBars < this.options.numBars){
        this.ctx.fillStyle = this.fstyle;
        this.ctx.beginPath();
        for(var i=nBars; i < this.options.numBars; i++){
            this.ctx.rect(0,(hb*i)+(.5*hl),w,hl);
        }
        this.ctx.closePath();
        this.ctx.fill();
    }

    this.ctx.restore();

    if(this.splabel){
        this.splabel.textContent = Math.floor(this.nextValue)/1000 + " Gbps";
        this.splabel.innerText = Math.floor(this.nextValue)/1000 + " Gbps";
    }

    // XXX: Add label for 'date'
    if(this.sptime && (newDate.valueOf() != 0)){
//        this.sptime.textContent = newDate.toLocaleFormat("%T %Z");
//        this.sptime.innerText = newDate.toLocaleFormat("%T %Z");
//        var ltime = newDate.getHours() + ":" + newDate.getMinutes() +
//            ":" + newDate.getSeconds() + " (browser TZ)";
//        var ltime = newDate.toLocaleTimeString;
        var ltime = String(newDate);
        this.sptime.textContent = ltime;
        this.sptime.innerText = ltime;
    }

    if(this.spdate && (newDate.valueOf() != 0)){
        this.spdate.textContent = newDate.toLocaleDateString();
        this.spdate.innerText = newDate.toLocaleDateString();
    }

    return;
}


// TODO: Get some opts from cookies?
var goSpeed = true;
var speed = null;

function loadDataSpeed(req) {

    if(!goSpeed) return;

    log("loadData: Data received:", Date());
    log("loadData: json:",req.responseText);
    var json = MochiKit.Async.evalJSONRequest(req);

    // XXX: Verify return succeeded.

    // XXX: Can remove when Jason corrects service
    // removes any trailing 0 data. (rrd is still modifying these)
    while(json.servdata.data.length > 1){
        var arrElem = json.servdata.data[json.servdata.data.length-1];
        var val;
        if(arrElem.length > 1){
            val = arrElem[1];
        }
        else{
            val = arrElem;
        }

        if(val != 0){
            break;
        }

        json.servdata.data.length--;
    }
            
    log("loadData: speed.appendData()", Date());
    speed.appendData(json.servdata.data);
    log("loadData: speed.data.length: ",speed.data.length);

    MochiKit.Async.callLater(speed.options.dataPeriod-1,newDataSpeed);
}

var getHost;
var getInterface;
var getDirection;
var getRefTime;

function newDataSpeed(){
    if(!goSpeed) return;

    var now = new Date();

    var query = "updateData.cgi";
    query +="?resolution="+defOptions.resolution+"&npoints="+defOptions.npoints+"&fakeServiceMode="+defOptions.fakeServiceMode+"&";
    if(!isNull(getHost)){
        query += "hostName="+getHost()+"&";
    }
    if(!isNull(getInterface)){
        query += "ifIndex="+getInterface()+"&";
    }
    if(!isNull(getDirection)){
        query += "direction="+getDirection()+"&";
    }
    if(!isNull(getRefTime)){
        query += "refTime="+getRefTime()+"&";
    }

    log("Fetch Data: ", now);
    // TODO: Change to POST and specify args
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest(query);
    doreq.addCallback(loadDataSpeed);
}

function startStopSpeed(){
    goSpeed = !goSpeed;

    if(goSpeed){
        $('start-stop-speed').value = "Stop";
        log("Starting data loop", Date());
        newDataSpeed();
    }
    else{
        log("Stopping data loop", Date());
        $('start-stop-speed').value = "Start";
    }
}

// TODO: Fix hardcoded id names for start/stop
var options = {
    "canvasName": "speedo",
    "startStopName": "start-stop-speed"
};


var speedInitRefTime;

function initSpeed(){
    // hack for names - eventually use 'type' attribute and fetch
    // HTML elements from DOM

    for(p in options){
        log("options[",p,"]: ",options[p]);
    }

    speedInitRefTime = new Date();
    speed = new Speed({"canvas": $(options.canvasName)});
    newDataSpeed();

    if(options.startStopName !== undefined){
        MochiKit.Signal.connect(options.startStopName, 'onclick',
            startStopSpeed);
    }
}

