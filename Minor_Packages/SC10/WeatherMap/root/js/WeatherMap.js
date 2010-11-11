var circuits = new Array();
var endpoints = new Array();
var icons = new Array();
var BACKGROUND_WIDTH;
var BACKGROUND_HEIGHT;
var BACKGROUND_IMG;


function loadWeatherMap(){
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest("conf/WeatherMap.xml");
    doreq.addCallback(initWeatherMap);
}

function initWeatherMap(req){
    log("initWeatherMap");

    var response = req.responseXML;
    loadBackground(response.getElementsByTagName('background'));
    loadEndpoints(response.getElementsByTagName('endPoint'));
    loadCircuits(response.getElementsByTagName('path'));
    loadIcons(response.getElementsByTagName('icon'));
    draw();
    getLinkState(); 
}

function loadBackground(props){
    log("loadBackground");
    if(props == null || props.length == 0){
        alert("background property not set in WeatherMap.xml"); 
        return;
    }
    BACKGROUND_WIDTH=props[0].getAttribute('width');
    BACKGROUND_HEIGHT=props[0].getAttribute('height');
    BACKGROUND_IMG=props[0].getAttribute('src');
    var canvas = document.getElementById('map_canvas');
    canvas.width = BACKGROUND_WIDTH;
    canvas.height = BACKGROUND_HEIGHT;
}

function loadCircuits(props){
    log("loadCircuits");
    if(props == null || props.length == 0){
        alert("circuit properties not set in WeatherMap.xml");
        return;
    }
    
    for(var i=0; i < props.length; i++){
        var circuit = new Object();
        circuit.active=0;
        var circuitPoints = new Array();
        var circuitVLANs = new Array();
        var link_endpoints = props[i].getElementsByTagName('endpoints');
        if(link_endpoints == null) {
            alert("no endpoints set for circuit in WeatherMap.xml");
            continue;
        }
        log("before pointList");
        var pointList = link_endpoints[0].getElementsByTagName('endpoint');
        log("after pointList");
        
        if(pointList == null || pointList.length < 2){
            alert("no points given for circuit in WeatherMap.xml");
            continue;
        }
        for(var j=0; j < pointList.length; j++){
            if (pointList[j].getAttribute('name')) {
                var name = pointList[j].getAttribute('name');
                if (endpoints[name]) {
                        circuitPoints.push(createPoint(endpoints[name]['x'], endpoints[name]['y']));
                } else {
                        alert("no endpoint named "+name);
                        circuitPoints.push(createPoint(0, 0));
                }
            } else {
                log("X: "+pointList[j].getAttribute('x')+" Y:"+pointList[j].getAttribute('y'));
                circuitPoints.push(createPoint(pointList[j].getAttribute('x'), pointList[j].getAttribute('y')));
            }
        }
        circuit.points = circuitPoints;
        var vlans = props[i].getElementsByTagName('vlan');
        if(vlans == null || vlans.length == 0){
            alert("no vlans set for circuit in WeatherMap.xml");
            continue;
        }
        for(var j=0; j < vlans.length; j++){
            circuitVLANs.push(vlans[j].firstChild.nodeValue);
        }
        circuit.vlans=circuitVLANs;
        //TODO: Better error checking
        circuit.src=props[i].getElementsByTagName('source')[0].firstChild.nodeValue;
        circuit.dest=props[i].getElementsByTagName('destination')[0].firstChild.nodeValue;
        var styleElem = props[i].getElementsByTagName('style');
        if(styleElem == null){
            alert("no style information provided for circuit");
            continue;
        }
        circuit.lineWidth=styleElem[0].getElementsByTagName('lineWidth')[0].firstChild.nodeValue;
        circuit.lineJoin=styleElem[0].getElementsByTagName('lineJoin')[0].firstChild.nodeValue;
        var initStrokeStyle = styleElem[0].getElementsByTagName('initStrokeColor')[0];
        circuit.initStrokeStyle='rgba(' + initStrokeStyle.getAttribute('r') + ','+ 
                                initStrokeStyle.getAttribute('g') + ',' +
                                initStrokeStyle.getAttribute('b') +','+
                                initStrokeStyle.getAttribute('a') + ')';
        circuit.strokeStyle=circuit.initStrokeStyle;
        var finalStrokeStyle = styleElem[0].getElementsByTagName('finalStrokeColor')[0];
        circuit.finalStrokeR=finalStrokeStyle.getAttribute('r');
        circuit.finalStrokeG=finalStrokeStyle.getAttribute('g');
        circuit.finalStrokeB=finalStrokeStyle.getAttribute('b');
        circuit.finalStrokeA=finalStrokeStyle.getAttribute('a');
        
        circuits.push(circuit);
    }
}

function loadEndpoints(props){
    if(props == null || props.length == 0){
        return;
    }
    
    for(var i=0; i < props.length; i++){
        var ep = new Object();
        ep.x = props[i].getAttribute('x');
        ep.y = props[i].getAttribute('y');

        if (props[i].getAttribute('icon')) {
            console.log("Found icon");
            ep.icon = props[i].getAttribute('icon');
        } else {
            ep.radius = props[i].getAttribute('radius');
            ep.innerRadius = props[i].getAttribute('innerRadius');
            ep.color1 = props[i].getAttribute('color1');
            ep.color2 = props[i].getAttribute('color2');
        }

        log("before get name");
        if (props[i].getAttribute('name')) {
            ep.name = props[i].getAttribute('name');
        }
        else {
            ep.name = "endpoint"+i;
        }

        log("after get name");
        endpoints[ep.name] = ep;
        log("after add");
    }
}

function loadIcons(props){
    if(props == null || props.length == 0){
        return;
    }
    
    for(var i=0; i < props.length; i++){
        var icon = new Object();
        icon.x = props[i].getAttribute('x');
        icon.y = props[i].getAttribute('y');
        icon.width = props[i].getAttribute('width');
        icon.height = props[i].getAttribute('height');
        icon.src = props[i].getAttribute('src');
        icons.push(icon);
    }
}

function draw(){
    var canvas = document.getElementById('map_canvas');
    var bgImg = new Image();

    if(canvas.getContext){
        bgImg.onload = function() {
            var ctx = canvas.getContext('2d');
            ctx.clearRect(0,0,BACKGROUND_WIDTH,BACKGROUND_HEIGHT);
            ctx.drawImage(bgImg, 0, 0, BACKGROUND_WIDTH,BACKGROUND_HEIGHT);

            //begin drawing
            for(var i=0; i < circuits.length; i++){
                var circuit = circuits[i];
                if(circuit == null || circuit.points == null){
                    continue;
                }
                //display parameters
                ctx.lineWidth = circuit.lineWidth;
                ctx.lineJoin = circuit.lineJoin;
                ctx.strokeStyle = circuit.strokeStyle;
                var points = circuit.points;
                ctx.beginPath();
                ctx.moveTo(points[0].x, points[0].y);
                for(var j=1; j < points.length; j++){
                    ctx.lineTo(points[j].x, points[j].y);
                }
                ctx.stroke();
                ctx.beginPath();
            }
            
           for(var j in endpoints){
                if (endpoints[j].icon) {
                    var iconImg = new Image();
                    var x = endpoints[j].x;
                    var y = endpoints[j].y;
                    var src = endpoints[j].icon;
                    iconImg.onload = function() {
                        var ctx = canvas.getContext('2d');
                        y -= iconImg.height/2;
                        x -= iconImg.width/2;
                        ctx.drawImage(iconImg, x, y);
                    }
                    iconImg.src = endpoints[j].icon;
                }
                else {
                    var radgrad = ctx.createRadialGradient(endpoints[j].x,endpoints[j].y,
                                                       endpoints[j].innerRadius,endpoints[j].x,
                                                       endpoints[j].y,endpoints[j].radius);
                    radgrad.addColorStop(0, endpoints[j].color1);
                    radgrad.addColorStop(1, endpoints[j].color2);
                    ctx.fillStyle = radgrad;
                    ctx.beginPath();
                    ctx.arc(endpoints[j].x,endpoints[j].y,endpoints[j].radius,0,Math.PI*2,true);
                    ctx.fill();
                }
           }
 
           for(var j=0; j < icons.length; j++){
               var iconImg = new Image();
               var x = icons[j].x;
               var y = icons[j].y;
               iconImg.onload = function() {
                   var ctx = canvas.getContext('2d');
                   y -= iconImg.height/2;
                   x -= iconImg.width/2;
                   ctx.drawImage(iconImg, x, y);
               }
               iconImg.src = icons[j].src;
           }
        }

        bgImg.src = BACKGROUND_IMG;
    }
}

/**
 * Title:       getLinkState
 * Arguments:   None
 * Purpose:     Call an external CGI to perform the calls to perfSONAR services, the data is returned in a JSON structure
 **/

function getLinkState() {
    // Call a 'local' CGI script that outputs data in JSON format
    var query = "wmap.cgi";
    log( "getPathStatus: Calling cgi script \"" + query + "\"" );
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest( query );
    doreq.addCallback( handleStateUpdate );
    MochiKit.Async.callLater( 20, getLinkState );
}

/**
 * Title:       handleUpdate
 * Arguments:   req - JSON data from external CGI
 * Purpose:     Process the JSON data, update the arrows/displays on the map accordingly
 **/

function handleStateUpdate( req ) {
    log( "handleUpdate: Data received \"" + Date() + "\"" );
    //log( "handleUpdate: JSON \"" + req.responseText + "\"" );
    var json = MochiKit.Async.evalJSONRequest( req );
    if( json == null ) { 
        return; 
    }

    for( var i = 0; i < json.perfsonardata.links.length; i++ ) {
        var src = json.perfsonardata.links[i].source.name; 
        var dst = json.perfsonardata.links[i].destination.name;       
        if(circuits[i].active == 1){
            circuits[i].strokeStyle = getColor( parseInt( json.perfsonardata.links[i].source.inval ) );
        }
    }
    draw();
}

function createPoint(x, y){
    var point = new Object();
    point.x= x;
    point.y = y;
    
    return point;
}

function getColor(value) {
    if( value >= 0 && value < 5242880 ) {
        return "rgb(0, 0, 255)";
    }
    else if( value >= 5242880 && value < 10485760 ) {
        return "rgb(0, 85, 255)";
    }
    else if( value >= 10485760 && value < 52428800) {
        return "rgb(0, 170, 255)";     
    }
    else if( value >= 52428800 && value < 104857600 ) {
        return "rgb(0, 255, 255)";
    }
    else if( value >= 104857600 && value < 524288000 ) {
        return "rgb(0, 255, 170)";
    }
    else if( value >= 524288000 && value < 1073741824 ) {
        return "rgb(0, 255, 0)";
    }
    else if( value >= 1073741824 && value < 2147483648 ) {
        return "rgb(85, 255, 0)";
    }
    else if( value >= 2147483648 && value < 3221225472 ) {
        return "rgb(170, 255, 0)";
    }
    else if( value >= 3221225472 && value < 4294967296 ) {
        return "rgb(255, 255, 0)";
    }
    else if( value >= 4294967296 && value < 5368709120 ) {
        return "rgb(255, 170, 0)";    
    }
    else if( value >= 5368709120 && value < 6442450944 ) {
        return "rgb(255, 85, 0)";
    }
    else if( value >= 6442450944 && value < 7516192768 ) {
        return "rgb(255, 0, 0)";
    }
    else if( value >= 7516192768 && value < 8589934592 ) {
        return "rgb(255, 0, 85)";
    }
    else if( value >= 8589934592 && value < 9663676416 ) {
        return "rgb(255, 0, 170)";
    }
    else if( value >= 9663676416 && value < 10737418240 ) {
        return "rgb(255, 0, 255)";
    }
    else if( value >= 10737418240 ) {
        return "rgb(170, 0, 255)";
    }
    else if( value == -1 ) {
        //gray
        return "rgb(128,128,128)";
    }
    else if( value == -2 ) {
        //white
        return "rgb(255,255,255)";
    }
    else {
        //black   
        return "rgb(0,0,0)";
    }
}
