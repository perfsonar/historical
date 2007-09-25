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

        // "dataStalePeriod":             // defaults to 2 * dataPeriod
        "staleAlpha": 0.4,          // how much to obscure colors
        "staleWidth": 0.75,          // how much to obscure colors

        "refreshPeriod": 0.100,// seconds
        "dataPeriod": 5,     // seconds
        "jitterPercent":    0.005,   // bounce a bit around value :)

        "labelName":  "speedo-value",
        "doIntro":  true
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

    if(this.options.maxValue <= 0){
        throw new Error("Speed: \"maxValue\" must be > 0");
    }

    if(this.options.dataPeriod < this.options.refreshPeriod){
        throw new Error("Speed: \"dataPeriod\" must be > \"refreshPeriod\"");
    }

    if(!this.options.dataStalePeriod){
        this.options.dataStalePeriod = 2 * this.options.dataPeriod;
    }

    // convert periods to milliseconds
    this.refreshPeriod = this.options.refreshPeriod * 1000;
    this.dataPeriod = this.options.dataPeriod * 1000;
    this.dataStalePeriod = this.options.dataStalePeriod * 1000;

    this.lastDataUpdate = this.nextDataUpdate = this.dataStale = 0;

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

    if(this.options.labelName){
        this.label = $(this.options.labelName);
        if(this.label.tagName != "P"){
            throw new Error("Speed: labelName should indicate \'P\' element");
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

    log("appendData: data has ",this.data.length);
    if(this.data.length > 0){
        if(this.data[this.data.length-1].length){
            log("lastdata: [",this.data[this.data.length-1][0],"][",this.data[this.data.length-1][1].toPrecision(9),"]");
        }
    }

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
    var stale = false;
    var nowDate = new Date();
    var now = nowDate.getTime();
    var newValue;
    if(now > this.nextDataUpdate){
        if(this.data && this.data.length){
            // update currentValue and nextValue
            var currentValue = this.data.shift();

            if(currentValue.length > 1){
                this.currentValue = currentValue[1];
            }
            else{
                this.currentValue = currentValue;
            }

            // update nextValue
            var nextValue;
            if(this.data.length < 1){
                nextValue = this.currentValue;
            }
            else{
                nextValue = this.data[0];
            }
            if(nextValue.length > 1){
                this.nextValue = nextValue[1];
            }
            else{
                this.nextValue = nextValue;
            }


            this.lastDataUpdate = now;
            this.nextDataUpdate = now + this.dataPeriod;
            this.dataStale = now + this.dataStalePeriod;


        }
        else{
            if(now > this.dataStale){
                stale = true;
                if(this.interval){
                    clearInterval(this.interval);
                    delete this.interval;
                }
            }
        }
        newValue = this.currentValue;
    }
    else{
        /*
         * linear (or other?) interpolation to approximate this update based
         * on target value and time.
         */
        if(!this.lastDataUpdate) this.lastDataUpdate = now;
        var timeDiff = now - this.lastDataUpdate;
        var valDiff = this.nextValue - this.currentValue;
        if(valDiff){
            newValue = this.currentValue +
                (valDiff * timeDiff / this.dataPeriod);
        }
        else{
            newValue = this.currentValue;
        }
    }

    var randValue = newValue;
    if(!stale){
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
    if(stale){
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

    if(this.label){
        this.label.textContent = Math.floor(this.nextValue) + " Mbps";
        this.label.innerText = Math.floor(this.nextValue) + " Mbps";
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
    //XXX: temporarily ignore last value
    if(json.servdata.data.length > 1){
        json.servdata.data.length -= 1;
    }

    log("loadData: speed.appendData()", Date());
    speed.appendData(json.servdata.data);
    log("loadData: speed.data.length: ",speed.data.length);

    MochiKit.Async.callLater(speed.options.dataPeriod-1,newDataSpeed);
}

var getHost;
var getInterface;
var getDirection;

function newDataSpeed(){
    if(!goSpeed) return;

    var query = "updateData.cgi";
    query +="?resolution="+defOptions.resolution+"&npoints="+defOptions.npoints+"&fakeServiceMode="+defOptions.fakeServiceMode+"&";
    if(!isNull(getHost)){
        query += "hostName="+getHost()+"&";
    }
    if(!isNull(getInterface)){
        query += "ifName="+getInterface()+"&";
    }
    if(!isNull(getDirection)){
        query += "direction="+getDirection()+"&";
    }

    log("Fetch Data: ", Date());
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


function initSpeed(){
    // hack for names - eventually use 'type' attribute and fetch
    // HTML elements from DOM

    for(p in options){
        log("options[",p,"]: ",options[p]);
    }

    speed = new Speed({"canvas": $(options.canvasName)});
    newDataSpeed();

    MochiKit.Signal.connect("start-stop-speed", 'onclick', startStopSpeed);
}

