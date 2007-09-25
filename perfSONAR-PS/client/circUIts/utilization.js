
// TODO: Get some opts from cookies?
var defOptionsUtil = {
        "resolution":   10,
        "npoints":   100,
        "fakeServiceMode": 0,
        "xOriginIsZero": false,
        "yAxis":[0,1000],
        "yTicks":[
        {label: "0", v: 0},
        {label: "200", v: 200},
        {label: "400", v: 400},
        {label: "600", v: 600},
        {label: "800", v: 800},
        {label: "1000", v: 1000},
        ],
    };
var layout = null;
var renderer = null;
var goUtil = true;

function loadDataUtil(req) {

    if(!goUtil) return;

    log("JSON:",req.responseText);
    log("PRE: evalJSON", Date());
    var json = MochiKit.Async.evalJSONRequest(req);
    log("POST: evalJSON", Date());

    log("json got:", json);

    layout.addDataset("sample",json.servdata.data);

    var i;
    var morig,mnew,sec;
    var mnDate = new Date(json.servdata.data[0][0]*1000);
    var mxDate = new Date(
            json.servdata.data[json.servdata.data.length-1][0]*1000);

    // TODO:
    // totally hacked assuming 1000 seconds of spread from min-max
    // Need to do something real here...

    // tick every 2 minutes
    sec = mnDate.getSeconds();
    morig = mnDate.getMinutes();
    mnew = Math.floor(morig/2.0) * 2;
    // make changes to Date object using increments of millisecs so
    // all date arithmetic is handled by "Date".
    i = json.servdata.data[0][0]-sec; // min boundry
    i -= (morig-mnew)*60;
    mnDate = new Date(i*1000);

    sec = mxDate.getSeconds();
    morig = mxDate.getMinutes();
    i=0;
    if(sec){
        morig++;
        i = 60-sec;
    }
    mnew = Math.ceil(morig/2.0) * 2;
    i += json.servdata.data[json.servdata.data.length-1][0]; // min boundry
    i += (mnew-morig)*60;
    mxDate = new Date(i*1000);

    var dateOptions = [];
    var ticks = [];
    var mn = mnDate.valueOf()/1000;
    var mx = mxDate.valueOf()/1000;

    dateOptions.xAxis = [mn,mx];
    for(i=mn;i<=mx;i+=120){
        mnDate = new Date(i*1000);
        mnew = mnDate.getMinutes();
        ticks.push({label: mnew, v: i});
    }
    dateOptions.xTicks = ticks;

    MochiKit.Base.update(layout.options,dateOptions);
    MochiKit.Base.update(renderer.options,dateOptions);

    layout.evaluate();
    renderer.clear();
    renderer.render();

    MochiKit.Async.callLater(defOptionsUtil.resolution,newDataUtil);
}

function newDataUtil(){
    if(!goUtil) return;

    var query = "updateData.cgi";
    query +="?resolution="+defOptionsUtil.resolution+"&npoints="+defOptionsUtil.npoints+"&fakeServiceMode="+defOptionsUtil.fakeServiceMode+"&";
    if(getHost){
        query += "hostName="+getHost()+"&";
    }
    if(getInterface){
        query += "ifName="+getInterface()+"&";
    }
    if(getDirection){
        query += "direction="+getDirection()+"&";
    }
    log("Fetch Data: ", Date());
    // TODO: Change to POST and specify args
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest(query);
    doreq.addCallback(loadDataUtil);
}

function startStopUtil(){
    goUtil = !goUtil;

    if(goUtil){
        $('start-stop-util').value = "Stop";
        log("Starting data loop", Date());
        newDataUtil();
    }
    else{
        log("Stopping data loop", Date());
        $('start-stop-util').value = "Start";
    }
}

function initGraph(){
    layout = new PlotKit.Layout("line",defOptionsUtil);

    newDataUtil();

    renderer = new SweetCanvasRenderer($('plot'),
            layout,defOptionsUtil);
    MochiKit.Signal.connect("start-stop-util", 'onclick', startStopUtil);
}
