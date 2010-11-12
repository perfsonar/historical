var canvas;
var endpoints;
var icons;
var links;
var background_image_src;
var background_image;
var background_height;
var background_width;
var background_color;
var background_loaded = 0;
var updateUrl = "out.json";

function initWeatherMap(newUpdateUrl) {
    canvas = document.getElementById('map_canvas');

    if (newUpdateUrl != null) {
	updateUrl = newUpdateUrl;
    }
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

    for(var icon_id in icons) {
        var icon = icons[icon_id];

        var iconImg = new Image();

        iconImg.icon = icon;
        icon.image_obj = iconImg;

        icon.loaded = 0;
        icon.drawn  = 0;

        iconImg.onload = function() {
            this.icon.loaded = 1;
            if (!this.icon["height"] && !this.icon["width"]) {
                this.icon.height = this.height;
                this.icon.width = this.width;
            } else if (this.icon["height"]) {
                this.icon.width = this.icon["height"]/this.height*this.width;
            } else if (this.icon["width"]) {
                this.icon.height = this.icon.width/this.width*this.height;
            }

            drawMap();
        }

        iconImg.src = icon.image;
    }

    for(var ep_id in endpoints) {
        log("Debug: Adding "+ep_id);
        var endpoint = endpoints[ep_id];

        if (endpoint['icon']) {
            var iconImg = new Image();

            iconImg.endpoint = endpoint;
            endpoint.image = iconImg;

            endpoint.loaded = 0;
            endpoint.drawn  = 0;

            iconImg.onload = function() {
                this.endpoint.loaded = 1;
                if (!this.endpoint["height"] && !this.endpoint["width"]) {
                    this.endpoint.height = this.height;
                    this.endpoint.width = this.width;
                } else if (this.endpoint["height"]) {
                    this.endpoint.width = this.endpoint["height"]/this.height*this.width;
                } else if (this.endpoint["width"]) {
                    this.endpoint.height = this.endpoint.width/this.width*this.height;
                }

                drawMap();
            }

            iconImg.src = endpoint.icon;
        }
        else {
            endpoint.loaded = 1;
            endpoint.drawn  = 0;
        }
    }

    drawMap();

    return false;
}

function drawMap() {
    log("Debug: drawMap()");

    if (background_loaded == 0) {
        log("Debug: no background");
        return;
    }

    for(var ep_id in endpoints) {
        var endpoint = endpoints[ep_id];
        if (endpoint['loaded'] == 0) {
                log("Debug: ep "+ep_id+" not loaded");
                return;
        }
    }

    for(var icon_id in icons) {
        var icon = icons[icon_id];
        if (icon['loaded'] == 0) {
                log("Debug: icon "+icon['image']+" not loaded");
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
    }else if (background_image != null) {
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

    log("Drew background");

    // fill in the height/width for the non-image endpoints
    for(var ep_id in endpoints) {
        var endpoint = endpoints[ep_id];
        if (endpoint.type == 'radial') {
	    log("Radial endpoint: "+ep_id);
            var outerRadius = 4.5;

            if (endpoint.outerRadius) {
                outerRadius = endpoint.outerRadius;
            }

            if (endpoint["height"] == null) {
		    endpoint["height"] = outerRadius * 2;
            }

            if (endpoint["width"] == null) {
            	endpoint["width"]  = outerRadius * 2;
	    }
        } else if (endpoint.type == 'hidden') {
            if (endpoint["height"] == null) {
                endpoint["height"] = 1;
            }

            if (endpoint["width"] == null) {
                endpoint["width"]  = 1;
            }
        }
    }

    var intra_link_count = new Array();

    for(var link_id in links) {
        var link = links[link_id];

        if (link["source"] == link["destination"]) {
            log("Debug: loopback found. ignoring.");
            continue;
        }

	if (endpoints[link["source"]] == null) {
		log("Debug: "+link["source"]+" is invalid endpoint");
		continue;
	}

	if (endpoints[link["destination"]] == null) {
		log("Debug: "+link["destination"]+" is invalid endpoint");
		continue;
	}

        log("Drawing line from "+link["source"]+" to "+link["destination"]);

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

        // we draw a "circle" around the pictures, and offset everything from that circle
        var ang = Math.atan2(dst_y-src_y,dst_x-src_x);

  //      log("Debug: src("+src_x+","+src_y+"), dst("+dst_x+","+dst_y+")");
        var src_radius = Math.sqrt(Math.pow(endpoints[link["source"]]["width"], 2) + Math.pow(endpoints[link["source"]]["height"], 2))/2;
 //       log("Debug: (width, height): ("+endpoints[link["source"]]["width"]+","+endpoints[link["source"]]["height"]+")");
        var dst_radius = Math.sqrt(Math.pow(endpoints[link["destination"]]["width"], 2) + Math.pow(endpoints[link["destination"]]["height"], 2))/2;

//        log("Debug: (src, dst): ("+src_radius+","+dst_radius+")");

        src_x += src_radius * Math.cos(ang);
        src_y += src_radius * Math.sin(ang);
        dst_x -= dst_radius * Math.cos(ang);
        dst_y -= dst_radius * Math.sin(ang);

   //     log("Debug: src("+src_x+","+src_y+"), dst("+dst_x+","+dst_y+"): post-y-mod");

        // Offset the arrow some if there are multiple links
        if (intra_link_count[num_links_between_id] > 1) {
            var ang = Math.PI - Math.atan2(dst_y-src_y,dst_x-src_x);
            var distance_offset = 2*15*(Math.floor((intra_link_count[num_links_between_id])/2))*(Math.pow(-1, intra_link_count[num_links_between_id]));

            var x_offset = Math.sin(ang)*distance_offset;
            var y_offset = Math.cos(ang)*distance_offset;

            src_x += x_offset;
            src_y += y_offset;
            dst_x += x_offset;
            dst_y += y_offset;
        }

        // Offset the arrow according to the src/dst image edges.
        var ang = Math.atan2(dst_y-src_y,dst_x-src_x);

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

	var srcdst_text = "";
	var dstsrc_text = "";
	var srcdst_value;
	var dstsrc_value;

        // measurement_results:[{"source_destination":{"unit":"bps","value":246528},"destination_source":{"unit":"bps","value":27648},"type":"utilization"}]
        for(var id in link["measurement_results"]) {
		var results = link["measurement_results"][id];
		//if (results["type"] != "utilization" && results["type"] != "last_throughput") {
		if (results["type"] != "utilization") {
			continue;
		}

		if (results["source_destination"]["value"] != null) {
			var value = results["source_destination"]["value"];
			srcdst_value = value;

			var units;
			if (value >= 1000*1000) {
				value /= 1000*1000;
				units = "M";
			} else {
				value = 0;
				units = "M";
			}
			if (value >= 1000) {
				value /= 1000;
				units = "G";
			}

			if (value > 10) {
				value = value.toFixed(0);
			} else {
				value = value.toFixed(1);
			}

			srcdst_text = value+units;
		}

		if (results["destination_source"]["value"] != null) {
			var value = results["destination_source"]["value"];
			var units;

			dstsrc_value = value;

			if (value >= 1000*1000) {
				value /= 1000*1000;
				units = "M";
			} else {
				value = 0;
				units = "M";
			}

			if (value >= 1000) {
				value /= 1000;
				units = "G";
			}

			if (value > 10) {
				value = value.toFixed(0);
			} else {
				value = value.toFixed(1);
			}

			dstsrc_text = value+units;
		}
	}

	log("Source Dest Text: "+srcdst_text);
	log("Dest Source Text: "+dstsrc_text);
	log("Source Dest Value: "+srcdst_value);
	log("Dest Source Value: "+dstsrc_value);

        //log("Debug: src_color: "+src_color);
        //log("Debug: dst_color: "+dst_color);
        //log("Debug: arrow_scale: "+arrow_scale);
        //log("Debug: (src_x, src_y): ("+src_x+","+src_y+")");
        //log("Debug: (dst_x, dst_y): ("+dst_x+","+dst_y+")");

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

            var srcdst_midpt_x = (src_x + midpt_x)/2;
            var dstsrc_midpt_x = (midpt_x + dst_x)/2;
            var srcdst_midpt_y = (src_y + midpt_y)/2;
            var dstsrc_midpt_y = (midpt_y + dst_y)/2;

            drawArrow(canvas_ctx, src_x, src_y, midpt_x, midpt_y, src_color, arrow_scale, 5 );
            drawArrow(canvas_ctx, dst_x, dst_y, midpt_x, midpt_y, dst_color, arrow_scale, 5 );

            if (srcdst_text) {
                var xoffset = -srcdst_text.length/2 * 5;
                var yoffset = -10;

		/*
		canvas_ctx.beginPath();
		canvas_ctx.moveTo(midpt_x,midpt_y);
		canvas_ctx.moveTo(midpt_x+srcdst_text.length * 5 ,midpt_y);
		canvas_ctx.moveTo(midpt_x+srcdst_text.length * 5 ,midpt_y+10);
		canvas_ctx.moveTo(midpt_x,midpt_y+10);
		canvas_ctx.moveTo(midpt_x,midpt_y);
		canvas_ctx.closePath();
		canvas_ctx.stroke();

		log("Output: "+midpt_x+":"+midpt_y);
		log("Output: "+(midpt_x+srcdst_text.length * 5)+":"+(midpt_y));
		log("Output: "+(midpt_x+srcdst_text.length * 5)+":"+(midpt_y+10));
		log("Output: "+midpt_x+":"+(midpt_y+10));
		log("Output: "+midpt_x+":"+midpt_y);
		*/

                drawString(canvas_ctx, srcdst_text, "rgb(0,0,0)", 10, srcdst_midpt_x + xoffset, srcdst_midpt_y + yoffset);
            }
            if (dstsrc_text) {
                var xoffset = -srcdst_text.length/2 * 5;
                var yoffset = -10;

                drawString(canvas_ctx, dstsrc_text, "rgb(0,0,0)", 10, dstsrc_midpt_x + xoffset, dstsrc_midpt_y + yoffset);
            }
        }
        else if (link["type"] == "unidirectional-line") {
            var prevLineWidth   = canvas_ctx.lineWidth;
            var prevStrokeStyle = canvas_ctx.strokeStyle;

            canvas_ctx.lineWidth     = 2 * arrow_scale;
            if (src_color != null) {
                canvas_ctx.strokeStyle   = src_color;
            }
            canvas_ctx.beginPath();
            canvas_ctx.moveTo(src_x,src_y);
            canvas_ctx.lineTo(dst_x, dst_y);
            canvas_ctx.stroke();
            canvas_ctx.strokeStyle = prevStrokeStyle;

            canvas_ctx.strokeStyle = prevStrokeStyle;
            canvas_ctx.lineWidth   = prevLineWidth;
        }
    }

    for(var ep_id in endpoints) {
        var endpoint = endpoints[ep_id];
        var x = parseInt(endpoint["x"], 10);
        var y = parseInt(endpoint["y"], 10);
        var height;
        var width;
        if (endpoint.type == "radial") {
            var innerColor = "#FFCE00";
            var outerColor = "#FF0000";
            var innerRadius = 1.0;
            var outerRadius = 4.5;

            if (endpoint.innerColor) {
                innerColor = endpoint.innerColor;
            }

            if (endpoint.outerColor) {
                outerColor = endpoint.outerColor;
            }

            if (endpoint.innerRadius) {
                innerRadius = endpoint.innerRadius;
            }

            if (endpoint.outerRadius) {
                outerRadius = endpoint.outerRadius;
            }

            endpoint["height"] = outerRadius * 2;
            endpoint["width"]  = outerRadius * 2;

            var prevFillStyle = canvas_ctx.fillStyle;
            var radgrad = canvas_ctx.createRadialGradient(endpoint.x,endpoint.y, innerRadius,endpoint.x, endpoint.y,outerRadius);
            radgrad.addColorStop(0, innerColor);
            radgrad.addColorStop(1, outerColor);
            canvas_ctx.fillStyle = radgrad;
            canvas_ctx.beginPath();
            canvas_ctx.arc(endpoint.x,endpoint.y,outerRadius,0,Math.PI*2,true);
            canvas_ctx.fill();
            canvas_ctx.fillStyle = prevFillStyle;

            //log("EP: "+endpoint["height"]+"/"+endpoint["width"]);
        } else if (endpoint.type == "icon" || (endpoint.type == null && endpoint.image != null)) {
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

            y -= height/2;
            x -= width/2;
            //log("Debug: Drawing "+ep_id+" image at ("+x+","+y+")");

                /*
            var new_rad = Math.sqrt(width*width+height*height)/2;
            canvas_ctx.strokeStyle = "rgb(0, 0, 0)";
            canvas_ctx.beginPath();
            canvas_ctx.arc(x + width/2, y + height/2, new_rad, 0, 2*Math.PI, true); 
            canvas_ctx.closePath();
            canvas_ctx.stroke();

            canvas_ctx.fillStyle = prevFill;
                */

            try {
                canvas_ctx.drawImage(endpoint["image"], x, y, width, height);
            }
            catch(err) {
                log("Error: "+err);
            };
        }
        //log("EP: "+endpoint["height"]+"/"+endpoint["width"]);
    }

    for(var icon_id in icons) {
        var icon = icons[icon_id];
        var x = parseInt(icon["x"], 10);
        var y = parseInt(icon["y"], 10);
        var height;
        var width;
        if (icon["height"] && icon["width"]) {
            height = icon["height"];
            width  = icon["width"];
        } else if (icon["height"]) {
            height = icon["height"];
            width = icon["height"]/icon.image.height*icon.image.width;
        } else if (icon["width"]) {
            width = icon["width"];
            height = icon["width"]/icon.image.width*icon.image.height;
        } else {
            height = icon.image.height;
            width = icon.image.width;
        }

        icon["height"] = height;
        icon["width"] = width;

        y -= height/2;
        x -= width/2;
        //log("Debug: Drawing "+icon_id+" image at ("+x+","+y+")");

        var prevFill = canvas_ctx.fillStyle;
        canvas_ctx.fillStyle = "rgb(255, 255, 255)";
        canvas_ctx.fillRect(x, y, width,height);
        canvas_ctx.fillStyle = prevFill;

        canvas_ctx.drawImage(icon.image_obj, x, y, width, height);
    }
}

/**
 * Title:       getMapState
 * Arguments:   None
 * Purpose:     Call an external CGI to obtain the new map to generate.
 **/

function getMapState() {
    // Call a 'local' CGI script that outputs data in JSON format
    var query = updateUrl;
    query += "?nonce="+(new Date().getTime());
    //log("Debug: getMapState: Calling cgi script \"" + query + "\"" );
    var doreq = MochiKit.Async.doSimpleXMLHttpRequest( query );
    doreq.addCallback( handleStateUpdate );
    MochiKit.Async.callLater( 120, getMapState );
}

/**
 * Title:       handleUpdate
 * Arguments:   req - JSON data from external CGI
 * Purpose:     Process the JSON data, update the arrows/displays on the map accordingly
 **/

function handleStateUpdate( req ) {
    //log("Debug: handleUpdate: Data received \"" + Date() + "\"" );
    //log("Debug: handleUpdate: JSON \"" + req.responseText + "\"" );
    var json;

    try {
        json = MochiKit.Async.evalJSONRequest( req );
        if( json == null ) { 
            //log("Debug: handleUpdate: got null json");
            return; 
        }
    } catch(err) {
        log("Error parsing json: "+err);
        return;
    }

    background_image_src = json["background"]["image"];
    background_color     = json["background"]["color"];
    background_height    = json["background"]["height"];
    background_width     = json["background"]["width"];
    endpoints            = json["endpoints"];
    links                = json["links"];
    icons                = json["icons"];

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
	//ctx.strokeStyle = col;
	ctx.strokeStyle = "rgb(0,0,0)";
	for (var i = 0; i < txt.length; i++) {
		drawSymbol(ctx, txt[i], ls, tx+xp, ty, fw, fh);
		xp += (txt[i]!="."?fw+cr:(fw/2)+cr);
	}
}

/*
function drawString( ctx, x, y, str ) {
    var size = 8;

    var i;
    for(i = 0; i < str.length; i++) {
	var symbol = str.substr(i, 1);
	console.log("Drawing("+i+","+x+","+y+"): "+symbol);
	drawSymbol( ctx, symbol, x, y, size );
	x += size;
    }
}
*/

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
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+(cw/2),(cw/2)-fc,deg2rad(180),0, false);
			ctx.arc(cx+(cw/2),(cy+ch)-(cw/2),(cw/2)-fc,0,deg2rad(180), false);
			ctx.closePath();
		break;
		case "1":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.1)+fc,cy+ch-fc);
			ctx.lineTo(cx+cw-fc,cy+ch-fc);
			ctx.moveTo(cx+(cw*0.666666),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.666666),cy+fc);
			ctx.lineTo(cx+(cw*0.25),cy+(ch*0.25));
		break;
		case "2":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+cw-fc,cy+(ch*0.8));
			ctx.lineTo(cx+cw-fc,cy+ch-fc);
			ctx.lineTo(cx+fc,cy+ch-fc);
			ctx.arc(cx+(cw/2),cy+(cw*0.425),(cw*0.425)-fc,deg2rad(45),deg2rad(-180), true);
		break;
		case "3":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.9)-fc,cy+fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-90),deg2rad(180), false);
		break;
		case "4":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.75),cy+ch-fc);
			ctx.lineTo(cx+(cw*0.75),cy+fc);
			ctx.moveTo(cx+cw-fc,cy+(ch*0.666666));
			ctx.lineTo(cx+fc,cy+(ch*0.666666));
			ctx.lineTo(cx+(cw*0.75),cy+fc);
			ctx.moveTo(cx+cw-fc,cy+ch-fc);
			ctx.lineTo(cx+(cw*0.5),cy+ch-fc);
		break;
		case "5":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-80),deg2rad(180), false);
		break;
		case "6":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+fc,cy+ch-(cw*0.5)-fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-180),deg2rad(180), false);
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.9)-fc,cy+fc);
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
		break;
		case "7":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.5),cy+ch-fc);
			ctx.lineTo(cx+cw-fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+fc);
			ctx.lineTo(cx+(cw*0.1)+fc,cy+(ch*0.25)-fc);
		break;
		case "8":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.92)-fc,cy+(cw*0.59));
			ctx.arc(cx+(cw/2),cy+(cw*0.45),(cw*0.45)-fc,deg2rad(25),deg2rad(-205), true);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-135),deg2rad(-45), true);
			ctx.closePath();
			ctx.moveTo(cx+(cw*0.79),cy+(ch*0.47));
			ctx.lineTo(cx+(cw*0.21),cy+(ch*0.47));
		break;
		case "9":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+cw-fc,cy+(cw*0.5));
			ctx.arc(cx+(cw/2),cy+(cw*0.5),(cw*0.5)-fc,deg2rad(0),deg2rad(360), false);
			ctx.bezierCurveTo(cx+cw-fc,cy+ch-fc,cx+cw-fc,cy+ch-fc,cx+(cw*0.1)+fc,cy+ch-fc);
		break;
		case "%":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+fc,cy+(ch*0.75));
			ctx.lineTo(cx+cw-fc,cy+(ch*0.25));
			ctx.moveTo(cx+(cw*0.505),cy+(cw*0.3));
			ctx.arc(cx+(cw*0.3),cy+(cw*0.3),(cw*0.3)-fc,deg2rad(0),deg2rad(360), false);
			ctx.moveTo(cx+(cw*0.905),cy+ch-(cw*0.3));
			ctx.arc(cx+(cw*0.7),cy+ch-(cw*0.3),(cw*0.3)-fc,deg2rad(0),deg2rad(360), false);
		break;
		case ".":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.25),cy+ch-fc-fc);
			ctx.arc(cx+(cw*0.25),cy+ch-fc-fc,fc,deg2rad(0),deg2rad(360), false);
			ctx.closePath();
		break;
		case "M":
			//log("I'm drawing "+symbol);
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
			//log("I'm drawing "+symbol);
            ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(180),deg2rad(-15), true);
			ctx.moveTo(cx+fc,cy+(ch*0.333333));
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.9)-fc,cy+fc);
			ctx.moveTo(cx+(cw*1.00),cy+(ch*0.5));
			ctx.lineTo(cx+(cw*0.60),cy+(ch*0.5));
		break;
		case "b":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+fc,cy+ch-(cw*0.5)-fc);
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-180),deg2rad(180), false);
			ctx.bezierCurveTo(cx+fc,cy+fc,cx+fc,cy+fc,cx+(cw*0.2)-fc,cy+fc);
			ctx.moveTo(cx+(cw*0.9)-fc,cy+fc);
		break;
		case "B":
			//log("I'm drawing "+symbol);
			ctx.moveTo(cx+(cw*0.92)-fc,cy+(cw*0.59));
			ctx.arc(cx+(cw/2),cy+(cw*0.45),(cw*0.45)-fc,deg2rad(25),deg2rad(-165), true);			
			ctx.arc(cx+(cw/2),cy+ch-(cw*0.5),(cw*0.5)-fc,deg2rad(-215),deg2rad(-45), true);
			ctx.closePath();
			ctx.moveTo(cx+(cw*0.79),cy+(ch*0.47));
			ctx.lineTo(cx+(cw*0.21),cy+(ch*0.47));
		break;
		default:
			log("Doing nothing");
		break;
	}	
	ctx.stroke();
}

/**
 * Title:       deg2rad
 * Arguments:   degrees - on a circle
 * Purpose:     Convert degree measure to Radiens
 **/
 
function deg2rad(degrees) {
	return Math.PI *degrees/180;
}


