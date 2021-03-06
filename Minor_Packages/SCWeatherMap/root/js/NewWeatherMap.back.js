var canvas;
var endpoints;
var links;
var background_image_src;
var background_image;
var background_height;
var background_width;
var background_color;
var background_loaded = 0;

function initWeatherMap() {
    canvas = document.getElementById('drawing');

/*
    var ep1 = new Array();
    ep1["id"] = "ep1";
    ep1["x"] = 30;
    ep1["y"] = 300;
    ep1["icon"] = "images/sc08_mini_logo2.png";

    var ep2 = new Array();
    ep2["id"] = "ep2";
    ep2["x"] = 200;
    ep2["y"] = 200;
    ep2["icon"] = "images/sc08_mini_logo2.png";

    var ep3 = new Array();
    ep3["id"] = "ep3";
    ep3["x"] = 800;
    ep3["y"] = 400;
    //ep3["icon"] = "images/sc08_mini_logo2.png";
    ep3["icon"] = "images/color_key.png";

    endpoints = new Array();
    endpoints[ep1["id"]] = ep1;
    endpoints[ep2["id"]] = ep2;
    endpoints[ep3["id"]] = ep3;

    var link1 = new Array();
    link1["source"] = "ep1";
    link1["destination"] = "ep2";
    link1["type"] = "unidirectional";
    link1["arrow-scale"] = 1;
    link1["source-destination"] = { "suggested-color": "rgb(255, 128, 0)" };

    var link3 = new Array();
    link3["source"] = "ep2";
    link3["destination"] = "ep1";
    link3["type"] = "unidirectional";
    link3["arrow-scale"] = 1;
    link3["source-destination"] = { "suggested-color": "rgb(0, 255, 0)" };

    var link2 = new Array();
    link2["source"] = "ep2";
    link2["destination"] = "ep3";
    link2["type"] = "bidirectional-pair";
    link2["arrow-scale"] = 1;
    link2["source-destination"] = { "suggested-color": "rgb(0, 255, 255)" };
    link2["destination-source"] = { "suggested-color": "rgb(0, 0, 255)" };

    links = new Array();
    links[0] = link1;
    links[1] = link1;
    links[2] = link2;
    links[3] = link2;
    links[4] = link2;
    links[5] = link2;
    links[6] = link2;
    links[7] = link2;
    links[8] = link2;
    links[9] = link2;
    links[10] = link1;
    links[11] = link3;
    links[12] = link3;
*/

    getMapState();
}

function refreshMap() {
    background_loaded = 0;

    if (background_image_src != null) {
        var bgImg = new Image();
        bgImg.onload = function() {
            background_image = this;
            background_loaded = 1;
            drawMap();
        }

        bgImg.src = background_image_src;
    }
    else {
        // if it's not a picture, it's already 'loaded'
        background_loaded = 1;
    }

    for(var link_id in links) {
        var link = links[link_id];

        var directions = [ "source", "destination" ];
        for(var direction_id in directions) {
            var direction = directions[direction_id];

            if (endpoints[link[direction]]["children"] == null) {
                endpoints[link[direction]]["children"] = new Array();
            }

            endpoints[link[direction]]["children"][link_id] = link;
        }
    }

    for(var ep_id in endpoints) {
        console.log("Adding "+ep_id);
        var endpoint = endpoints[ep_id];

        if (endpoint['icon']) {
            var iconImg = new Image();

            iconImg.endpoint = endpoint;
            endpoint.image = iconImg;

            endpoint.loaded = 0;
            endpoint.drawn  = 0;

            iconImg.onload = function() {
                this.endpoint.loaded = 1;
                drawMap();
            }

            iconImg.src = endpoint.icon;
        }
    }

    return false;
}

function drawMap() {
    if (background_loaded == 0) {
        console.log("no background");
        return;
    }

    for(var ep_id in endpoints) {
        var endpoint = endpoints[ep_id];
        if (endpoint['loaded'] == 0) {
                console.log("ep "+endpoint['name']+" not loaded");
                return;
        }
    }

    var canvas_ctx = canvas.getContext('2d');

    var height;
    if (background_height != null) {
        height = background_height;
    } else if (background_image != null) {
        height = background_image.height;
    }

    var width;
    if (background_width != null) {
        width = background_width;
    } else if (background_image != null) {
        width = background_image.width;
    }

    canvas_ctx.clearRect(0,0,width,height);
    if (background_image) {
        canvas_ctx.drawImage(background_image, 0, 0, width,height);
    }
    else if (background_color) {
        var prevFill = canvas_ctx.fillStyle;
        canvas_ctx.fillStyle = background_color;
        canvas_ctx.fillRect(0, 0, width,height);
        canvas_ctx.fillStyle = prevFill;
    }

    for(var ep_id in endpoints) {
        var endpoint = endpoints[ep_id];
        var x = parseInt(endpoint["x"], 10);
        var y = parseInt(endpoint["y"], 10);
        var height;
        var width;
        if (endpoint["height"] && endpoint["width"]) {
            height = endpoint["height"];
            width  = endpoint["width"];
        } else if (endpoint["height"]) {
            height = endpoint["height"];
            width = endpoint["height"]/endpoint.image.height*endpoint.image.width;
        } else if (endpoint["width"]) {
            width = endpoint["width"];
            height = endpoint["width"]/endpoint.image.width*endpoint.image.height;
        } else {
            height = endpoint.image.height;
            width = endpoint.image.width;
        }

        endpoint["height"] = height;
        endpoint["width"] = width;

        console.log("Drawing "+endpoint["id"]+" image at ("+x+","+y+")");
        y -= height/2;
        x -= width/2;
        console.log("Drawing "+endpoint["id"]+" image at ("+x+","+y+")");
        canvas_ctx.drawImage(endpoint.image, x, y, width, height);
    }
 
    var intra_link_count = new Array();

    for(var link_id in links) {
        var link = links[link_id];

        if (link["source"] == link["destination"]) {
            console.log("loopback found. ignoring.");
            continue;
        }

        var num_links_between_id;

        if (link["source"] < link["destination"]) {
            num_links_between_id = link["source"]+link["destination"];
        }
        else {
            num_links_between_id = link["destination"]+link["source"];
        }

        if (intra_link_count[num_links_between_id] == null) {
            intra_link_count[num_links_between_id] = 1;
        }
        else {
            intra_link_count[num_links_between_id]++;
        }

        var src_x = parseInt(endpoints[link["source"]]["x"], 10);
        var src_y = parseInt(endpoints[link["source"]]["y"], 10); 
        var dst_x = parseInt(endpoints[link["destination"]]["x"], 10);
        var dst_y = parseInt(endpoints[link["destination"]]["y"], 10);

        // no x movement if it's up/down
        if (src_x < dst_x) {
            src_x += endpoints[link["source"]]["width"]/2;
            dst_x -= endpoints[link["destination"]]["width"]/2;
        } else if (src_x > dst_x) {
            src_x -= endpoints[link["source"]]["width"]/2;
            dst_x += endpoints[link["destination"]]["width"]/2;
        }

        if (src_y < dst_y) {
            src_y += endpoints[link["source"]]["height"]/2;
            dst_y -= endpoints[link["destination"]]["height"]/2;
        } else if (src_y > dst_y) {
            src_y -= endpoints[link["source"]]["height"]/2;
            dst_y += endpoints[link["destination"]]["height"]/2;
        }

        // Offset the arrow some if there are multiple links
        if (intra_link_count[num_links_between_id] > 1) {
            var ang = Math.PI - Math.atan2(dst_y-src_y,dst_x-src_x);
            var distance_offset = 2*8*(Math.floor((intra_link_count[num_links_between_id])/2))*(Math.pow(-1, intra_link_count[num_links_between_id]));

            var x_offset = Math.sin(ang)*distance_offset;
            var y_offset = Math.cos(ang)*distance_offset;

            src_x += x_offset;
            src_y += y_offset;
            dst_x += x_offset;
            dst_y += y_offset;
        }

        var src_color;
        var dst_color;
        var arrow_scale;

        if (link["arrow_scale"]) {
                arrow_scale = link["arrow_scale"];
        } else {
                arrow_scale = 1;
        }

        if (link["suggested-colors"]) {
            if (link["suggested-colors"]["source-destination"]) {
                src_color = link["suggested-colors"]["source-destination"];
            }
            if (link["suggested-colors"]["destination-source"]) {
                dst_color = link["suggested-colors"]["destination-source"];
            }
        }

        console.log("src_color: "+src_color);
        console.log("dst_color: "+dst_color);
        console.log("arrow_scale: "+arrow_scale);
        console.log("(src_x, src_y): ("+src_x+","+src_y+")");
        console.log("(dst_x, dst_y): ("+dst_x+","+dst_y+")");

        if (link["type"] == "bidirectional") {
            drawArrow(canvas_ctx, src_x, src_y, dst_x, dst_y, src_color, arrow_scale );
            drawArrow(canvas_ctx, dst_x, dst_y, src_x, src_y, src_color, arrow_scale );
        }
        else if (link["type"] == "unidirectional") {
            drawArrow(canvas_ctx, src_x, src_y, dst_x, dst_y, src_color, arrow_scale );
        }
        else if (link["type"] == "bidirectional-pair") {
            var midpt_x = (src_x + dst_x)/2;
            var midpt_y = (src_y + dst_y)/2;

            drawArrow(canvas_ctx, src_x, src_y, midpt_x, midpt_y, src_color, arrow_scale );
            drawArrow(canvas_ctx, dst_x, dst_y, midpt_x, midpt_y, dst_color, arrow_scale );
        }
    }
}

/**
 * Title:       getMapState
 * Arguments:   None
 * Purpose:     Call an external CGI to obtain the new map to generate.
 **/

function getMapState() {
    // Call a 'local' CGI script that outputs data in JSON format
    var query = "wmap.cgi";
    log( "getMapState: Calling cgi script \"" + query + "\"" );
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest( query );
    doreq.addCallback( handleStateUpdate );
    MochiKit.Async.callLater( 20, getMapState );
}

/**
 * Title:       handleUpdate
 * Arguments:   req - JSON data from external CGI
 * Purpose:     Process the JSON data, update the arrows/displays on the map accordingly
 **/

function handleStateUpdate( req ) {
    log( "handleUpdate: Data received \"" + Date() + "\"" );
    log( "handleUpdate: JSON \"" + req.responseText + "\"" );
    var json = MochiKit.Async.evalJSONRequest( req );
    if( json == null ) { 
        log("handleUpdate: got null json");
        return; 
    }

    background_image_src = json["background"]["image"];
    background_color     = json["background"]["color"];
    background_height    = json["background"]["height"];
    background_width     = json["background"]["width"];
    endpoints            = json["endpoints"];
    links                = json["links"];

    refreshMap();
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

