/**
 * Title:      wmap.js
 * Purpose:    Javascript Mapping library for perfSONAR powered weathermaps
 * Version:    $Id$
 * Author:     Jason Zurawski - zurawski at internet2 dot edu
 *             Andrew Lake - alake at internet2 dot edu
 *  
 * To join the 'perfSONAR-PS' mailing list, please visit:
 * 
 *   https://mail.internet2.edu/wws/info/i2-perfsonar
 * 
 * The perfSONAR-PS subversion repository is located at:
 * 
 *   http://anonsvn.internet2.edu/svn/perfSONAR-PS
 * 
 * Questions and comments can be directed to the author, or the mailing list.  Bugs,
 * feature requests, and improvements can be directed here:
 * 
 *   http://code.google.com/p/perfsonar-ps/issues/list
 * 
 * You should have received a copy of the Internet2 Intellectual Property Framework along
 * with this software.  If not, see <http://www.internet2.edu/membership/ip.html>
 * 
 * Copyright (c) 2008, Internet2
 * 
 * All rights reserved.
 **/

/**
 * Global variables
 **/

var file = "conf/wmap.xml";
var refresh = 10;
var paths = new Array();
var MAP_WIDTH;
var MAP_HEIGHT;
var MAP_IMG;

/**
 * Title:       loadWeatherMap
 * Arguments:   None
 * Purpose:     Call this from HTML page. 
 **/

function loadWeatherMap() {
    log( "loadWeatherMap: Using map file \"" + file + "\"" );
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest( file );
    doreq.addCallback( initWeatherMap );
}

/**
 * Title:       initWeatherMap
 * Arguments:   req - callback information
 * Purpose:     Perform first steps to load weathermap functionality
 **/

function initWeatherMap( req ) {
    log( "initWeatherMap: req value \"" + req + "\"" );
    var response = req.responseXML;
    loadMap( response.getElementsByTagName( 'map' ) );
    loadPaths( response.getElementsByTagName( 'path' ) );
    draw();
    getPathStatus(); 
}

/**
 * Title:       loadMap
 * Arguments:   props - properties of the map tag in the configuration file
 * Purpose:     Sort out all of the properties from the configuration file
 **/

function loadMap( props ) {
    if( props == null || props.length == 0 ) {
        alert( "loadMap: Map properties (e.g. height/width/source) not set in \"" + file + "\"" ); 
        return;
    }
    log( "loadMap: prop.length is set to \"" + props.length + "\"" );
    MAP_WIDTH = props[0].getAttribute( 'width' );
    MAP_HEIGHT = props[0].getAttribute( 'height' );
    MAP_IMG = props[0].getAttribute( 'src' );
    var canvas = document.getElementById( 'map_canvas' );
    canvas.width = MAP_WIDTH;
    canvas.height = MAP_HEIGHT;
}

/**
 * Title:       loadPaths
 * Arguments:   props - paths from configuration file
 * Purpose:     For each path, extract the useful bits for display
 **/

function loadPaths( props ) {
    if( props == null || props.length == 0 ){
        alert( "loadPaths: No paths defined in \"" + file + "\"" ); 
        return;
    }
    
    for( var i = 0; i < props.length; i++ ) {
        var path = new Object();
        var pathPoints = new Array();
        
        // prepare arrow (will draw both in/out)
        var points = props[i].getElementsByTagName( 'arrow' );
        if( points == null ){
            alert( "loadPaths: No points set for path in " + file );
            continue;
        }
        var pointList = points[0].getElementsByTagName( 'point' );
        if( pointList == null || pointList.length < 2 ) {
            alert( "loadPaths: No points given for path in " + file );
            continue;
        }
        for( var j = 0; j < pointList.length; j++ ) {
            pathPoints.push( createPoint( pointList[j].getAttribute( 'x' ), pointList[j].getAttribute( 'y' ) ) );
        }
        path.points = pathPoints;
        
        // set all the path junk
        path.src=props[i].getElementsByTagName( 'source' )[0].firstChild.nodeValue;
        path.dest=props[i].getElementsByTagName( 'destination' )[0].firstChild.nodeValue;
        var styleElem = props[i].getElementsByTagName( 'style' );
        if( styleElem == null ){
            alert( "loadPaths: No style information provided for path" );
            continue;
        }
        path.lineWidth = styleElem[0].getElementsByTagName( 'lineWidth' )[0].firstChild.nodeValue;
        path.lineJoin = styleElem[0].getElementsByTagName( 'lineJoin' )[0].firstChild.nodeValue;
        var initStrokeStyle = styleElem[0].getElementsByTagName( 'initStrokeColor' )[0];
        path.initStrokeStyle = 'rgb(' + initStrokeStyle.getAttribute( 'r' ) + ',' + initStrokeStyle.getAttribute( 'g' ) + ',' + initStrokeStyle.getAttribute( 'b' ) + ')';

        path.strokeStyleIn = path.initStrokeStyle;
        path.strokeStyleOut = path.initStrokeStyle;

        // set the color properties
        var finalStrokeStyle = styleElem[0].getElementsByTagName( 'finalStrokeColor' )[0];
        var finalStrokeStyleIn = finalStrokeStyle.getElementsByTagName( 'inColor' )[0];
        path.finalStrokeInR=finalStrokeStyleIn.getAttribute( 'r' );
        path.finalStrokeInG=finalStrokeStyleIn.getAttribute( 'g' );
        path.finalStrokeInB=finalStrokeStyleIn.getAttribute( 'b' );

        var finalStrokeStyleOut = finalStrokeStyle.getElementsByTagName( 'outColor' )[0];
        path.finalStrokeOutR=finalStrokeStyleOut.getAttribute( 'r' );
        path.finalStrokeOutG=finalStrokeStyleOut.getAttribute( 'g' );
        path.finalStrokeOutB=finalStrokeStyleOut.getAttribute( 'b' );
        
        paths.push( path );
    }
}

/**
 * Title:       draw
 * Arguments:   None
 * Purpose:     Draw the arrows to the html page
 **/

function draw() {

    var canvas = document.getElementById( 'map_canvas' );
    var bgImg = new Image();    
    if( canvas.getContext ){

        var ctx = canvas.getContext('2d');
        bgImg.src = MAP_IMG;
        bgImg.onload = function() {
            
            ctx.clearRect( 0, 0, MAP_WIDTH, MAP_HEIGHT );

            //begin drawing
            for( var i = 0; i < paths.length; i++ ) {
                var path = paths[i];
                if( path == null || path.points == null ) {
                    alert( "draw: Paths and/or arrow points not defined" );
                    continue;
                }

                //in arrow
                ctx.lineWidth = path.lineWidth;
                ctx.lineJoin = path.lineJoin;
                ctx.strokeStyle = path.strokeStyleIn;
                var points = path.points;
                drawLineArrow(ctx, points[0].x, points[0].y, points[1].x, points[1].y);

                var m = ( ( points[1].y - points[0].y ) / ( points[1].x - points[0].x ) );
                var b = points[0].y - ( m * points[0].x );

/*                
                if ( points[0].x > points[1].x ) {
                    drawString( ctx, "1MB", "#000000", 6, points[1].x-(2*path.lineWidth), points[1].y-(5*path.lineWidth) );
                    drawString( ctx, "2MB", "#000000", 6, points[0].x-(1*path.lineWidth), points[0].y+(7*path.lineWidth) );
                }
                else {
                    drawString( ctx, "3MB", "#000000", 6, points[1].x-(7*path.lineWidth), points[1].y+(1*path.lineWidth) );
                    drawString( ctx, "4MB", "#000000", 6, points[0].x+(5*path.lineWidth), points[0].y-(5*path.lineWidth) );
                }                
*/
                //out arrow                
                ctx.lineWidth = path.lineWidth;
                ctx.lineJoin = path.lineJoin;
                ctx.strokeStyle = path.strokeStyleOut;
                
                if ( points[0].x == points[1].x ) {
                    if ( points[0].y <= points[1].y ) { 
                        drawLineArrow(ctx, points[1].x+(1.5*path.lineWidth), points[1].y, points[0].x+(1.5*path.lineWidth), points[0].y);
                    }
                    else {
                        drawLineArrow(ctx, points[1].x-(1.5*path.lineWidth), points[1].y, points[0].x-(1.5*path.lineWidth), points[0].y);
                    }
                }
                else {
                    if ( points[0].x >= points[1].x ) {
                        drawLineArrow(ctx, points[1].x+(1), ((m*points[1].x+(1))+b+(2*path.lineWidth)), points[0].x+(1), ((m*points[0].x+(1))+b+(2*path.lineWidth)));

                    }
                    else {
                        drawLineArrow(ctx, points[1].x+(3), ((m*points[1].x+(3))+b-(2*path.lineWidth)), points[0].x+(3), ((m*points[0].x+(3))+b-(2*path.lineWidth)));
                    }
                }
            }
            ctx.drawImage( bgImg, 0, 0, MAP_WIDTH, MAP_HEIGHT );
        }

    }
}

/**
 * Title:       getPathStatus
 * Arguments:   None
 * Purpose:     Call an external CGI to perform the calls to perfSONAR services, the data is returned in a JSON structure
 **/

function getPathStatus() {
    // Call a 'local' CGI script that outputs data in JSON format
    var query = "wmap.cgi";
    log( "getPathStatus: Calling cgi script \"" + query + "\"" );
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest( query );
    doreq.addCallback( handleUpdate );
    MochiKit.Async.callLater( refresh, getPathStatus );
}

/**
 * Title:       handleUpdate
 * Arguments:   req - JSON data from external CGI
 * Purpose:     Process the JSON data, update the arrows/displays on the map accordingly
 **/

function handleUpdate( req ) {
    log( "handleUpdate: Data received \"" + Date() + "\"" );
    log( "handleUpdate: JSON \"" + req.responseText + "\"" );
    var json = MochiKit.Async.evalJSONRequest( req );
    if( json == null ) { 
        return; 
    }
    for( var i = 0; i < json.perfsonardata.links.length; i++ ) {
        var src = json.perfsonardata.links[i].source.name; 
        var dst = json.perfsonardata.links[i].destination.name;       

        paths[i].strokeStyleIn = getColor( parseInt( json.perfsonardata.links[i].source.inval ) ); 
        paths[i].strokeStyleOut = getColor( parseInt( json.perfsonardata.links[i].source.outval ) );
    }
    draw();
}

/**
 * Title:       getColor
 * Arguments:   value - measurement value
 * Purpose:     return the proper arrow color for the given measurement
 **/

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

/**
 * Title:       createPoint
 * Arguments:   None
 * Purpose:     Draw the physical arrow(s)
 **/

function createPoint(x, y) {
    var point = new Object();
    point.x = parseInt(x);
    point.y = parseInt(y);
    
    return point;
}

var arrow = [
    [ 2, 0 ],
    [ -10, 0 ],
    [ -10, 4]
];

/**
 * Title:       drawFilledPolygon
 * Arguments:   ctx   - canvas
 *              shape - in our case an arrow
 * Purpose:     Draw the 'filled' arrohead.
 **/

function drawFilledPolygon( ctx, shape ) {
    ctx.beginPath();
    ctx.moveTo(shape[0][0],shape[0][1]);
    for( p in shape ) {
        if ( p > 0 ) {
            ctx.lineTo(shape[p][0],shape[p][1]);
        }
    }
    ctx.lineTo(shape[0][0],shape[0][1]);
    //ctx.fill();
    ctx.stroke();
}

/**
 * Title:       translateShape
 * Arguments:   shape - In our case only an arrow
 *              x     - coordinate x
 *              y     - coordinate y
 * Purpose:     Translate the point values of the shape
 **/

function translateShape( shape, x, y ) {
    var rv = [];
    for( p in shape ) {
        rv.push( [ shape[p][0] + x, shape[p][1] + y ] );
    }
    return rv;
}

/**
 * Title:       rotateShape
 * Arguments:   shape - In our case only an arrow
 *              ang   - The arc tangent angle of the arrow shaft
 * Purpose:     Rotate each point in the shape.  
 **/

function rotateShape( shape, ang ) {
    var rv = [];
    for ( p in shape ) {
        rv.push( rotatePoint( ang, shape[p][0], shape[p][1] ) );
    }
    return rv;
}

/**
 * Title:       rotatePoint
 * Arguments:   ang - arc tangent angle from affow shaft
 *              x   - coordinate x
 *              y   - coordinate y
 * Purpose:     Rotate the 'point' from the guidlines in the arrow object given
 *              that the arrow shaft will be pointing in different directions
 **/

function rotatePoint( ang, x, y ) {
    return [
        ( x * Math.cos( ang ) ) - ( y * Math.sin( ang ) ),
        ( x * Math.sin( ang ) ) + ( y * Math.cos( ang ) )
    ];
}

/**
 * Title:       drawLineArrow
 * Arguments:   ctx - canvas object
 *              x1  - 1st coordinate x
 *              y1  - 1st coordinate y
 *              x2  - 2nd coordinate x
 *              y2  - 2nd coordinate y
 * Purpose:     Draw an arrow between 2 points
 **/

function drawLineArrow( ctx, x1, y1, x2, y2 ) {
    ctx.beginPath();
    ctx.moveTo( x1, y1 );
    ctx.lineTo( x2, y2 );
    ctx.stroke();
    var ang = Math.atan2( y2 - y1, x2 - x1 );
    drawFilledPolygon(ctx, translateShape( rotateShape ( arrow, ang ), x2, y2 ) );
}

/**
 * Title:       deg2rad
 * Arguments:   degrees - on a circle
 * Purpose:     Convert degree measure to Radiens
 **/
 
function deg2rad(degrees) {
	return Math.PI *degrees/180;
}

/**
 * Title:       drawString
 * Arguments:   ctx - Canvas element
 *              txt - Text string to write
 *              col - color
 *              fh  - font 'size'
 *              tx  - x coordinate
 *              ty  - y coordinate
 * Purpose:     Draw various string characters
 **/

function drawString(ctx, txt, col, fh, tx, ty) {
	var fw = fh*0.666666; 
	var lw = fh*0.125;  
	var ls = lw/2; 
	var xp = 0; 
	var cr = lw; 
	ctx.lineCap = "round"; 
	ctx.lineJoin = "round"
	ctx.lineWidth = lw; 
	ctx.strokeStyle = col;
	for (var i = 0; i < txt.length; i++) {
		drawSymbol(ctx, txt[i], ls, tx+xp, ty, fw, fh);
		xp += (txt[i]!="."?fw+cr:(fw/2)+cr);
	}
}

/**
 * Title:       drawSymbol
 * Arguments:   ctx    - Canvas element
 *              symbol - Character to draw
 *              fc     - offset
 *              cx     - x coordinate
 *              cy     - y coordinate
 *              ch     - Character size
 * Purpose:     Draws a specific symbol
 **/
 
function drawSymbol( ctx, symbol, fc, cx, cy, cw, ch ) {
	ctx.beginPath();
	switch ( symbol ) {
		case "0":
			ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+(cw/2),(cw/2)-fc,deg2rad(180),0, false);
			ctx.arc(cx+(cw/2),(cy+ch)-(cw/2),(cw/2)-fc,0,deg2rad(180), false);
			ctx.closePath();
		break;
		case "1":
			ctx.moveTo(cx+(cw*0.1)+fc,cy+ch-fc);
			ctx.lineTo(cx+cw-fc,cy+ch-fc);
			ctx.moveTo(cx+(cw*0.666666),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.666666),cy+fc);
			ctx.lineTo(cx+(cw*0.25),cy+(ch*0.25));
		break;
		case "2":
			ctx.moveTo(cx+cw-fc,cy+(ch*0.8));
			ctx.lineTo(cx+cw-fc,cy+ch-fc);
			ctx.lineTo(cx+fc,cy+ch-fc);
			ctx.arc(cx+(cw/2),cy+(cw*0.425),(cw*0.425)-fc,deg2rad(45),deg2rad(-180), true);
		break;
		case "3":
			ctx.moveTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.9)-fc,cy+fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-90),deg2rad(180), false);
		break;
		case "4":
			ctx.moveTo(cx+(cw*0.75),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.75),cy+fc);
			ctx.moveTo(cx+cw-fc,cy+(ch*0.666666));
			ctx.lineTo(cx+fc,cy+(ch*0.666666));
			ctx.lineTo(cx+(cw*0.75),cy+fc);
			ctx.moveTo(cx+cw-fc,cy+ch-fc);
			ctx.lineTo(cx+(cw*0.5),cy+ch-fc);
		break;
		case "5":
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-80),deg2rad(180), false);
		break;
		case "6":
			ctx.moveTo(cx+fc,cy+ch-(cw*0.5)-fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-180),deg2rad(180), false);
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.9)-fc,cy+fc);
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
		break;
		case "7":
			ctx.moveTo(cx+(cw*0.5),cy+ch-fc);
			ctx.lineTo(cx+cw-fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+(ch*0.25)-fc);
		break;
		case "8":
			ctx.moveTo(cx+(cw*0.92)-fc,cy+(cw*0.59));
			ctx.arc(cx+(cw/2),cy+(cw*0.45),(cw*0.45)-fc,deg2rad(25),deg2rad(-205), true);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-135),deg2rad(-45), true);
			ctx.closePath();
			ctx.moveTo(cx+(cw*0.79),cy+(ch*0.47));
			ctx.lineTo(cx+(cw*0.21),cy+(ch*0.47));
		break;
		case "9":
			ctx.moveTo(cx+cw-fc,cy+(cw*0.5));
			ctx.arc(cx+(cw/2),cy+(cw*0.5),(cw*0.5)-fc,deg2rad(0),deg2rad(360), false);
			ctx.bezierCurveTo(cx+cw-fc,cy+ch-fc,cx+cw-fc,cy+ch-fc,cx+(cw*0.1)+fc,cy+ch-fc);
		break;
		case "%":
			ctx.moveTo(cx+fc,cy+(ch*0.75));
			ctx.lineTo(cx+cw-fc,cy+(ch*0.25));
			ctx.moveTo(cx+(cw*0.505),cy+(cw*0.3));
			ctx.arc(cx+(cw*0.3),cy+(cw*0.3),(cw*0.3)-fc,deg2rad(0),deg2rad(360), false);
			ctx.moveTo(cx+(cw*0.905),cy+ch-(cw*0.3));
			ctx.arc(cx+(cw*0.7),cy+ch-(cw*0.3),(cw*0.3)-fc,deg2rad(0),deg2rad(360), false);
		break;
		case ".":
			ctx.moveTo(cx+(cw*0.25),cy+ch-fc-fc);
			ctx.arc(cx+(cw*0.25),cy+ch-fc-fc,fc,deg2rad(0),deg2rad(360), false);
			ctx.closePath();
		break;
		case "M":
			ctx.moveTo(cx+(cw*0.083),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.083),cy+fc);	
            ctx.moveTo(cx+(cw*0.083),cy+fc);	
            ctx.lineTo(cx+(cw*0.4167),cy+ch-fc);
            ctx.moveTo(cx+(cw*0.4167),cy+ch-fc);
            ctx.lineTo(cx+(cw*0.75),cy+fc);	
			ctx.moveTo(cx+(cw*0.75),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.75),cy+fc);		
		break;
		case "G":
            ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(180),deg2rad(-15), true);
			ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.9)-fc,cy+fc);
			ctx.moveTo(cx+(cw*1.00),cy+(ch*0.5));
			ctx.lineTo(cx+(cw*0.60),cy+(ch*0.5));
		break;
		case "b":
			ctx.moveTo(cx+fc,cy+ch-(cw*0.5)-fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-180),deg2rad(180), false);
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.2)-fc,cy+fc);
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
		break;
		case "B":
			ctx.moveTo(cx+(cw*0.92)-fc,cy+(cw*0.59));
			ctx.arc(cx+(cw/2),cy+(cw*0.45),(cw*0.45)-fc,deg2rad(25),deg2rad(-165), true);			
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-215),deg2rad(-45), true);
			ctx.closePath();
			ctx.moveTo(cx+(cw*0.79),cy+(ch*0.47));
			ctx.lineTo(cx+(cw*0.21),cy+(ch*0.47));
		break;
		default:
		break;
	}	
	ctx.stroke();
}

