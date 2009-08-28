
google.load("visualization", "1", {packages:["areachart"]});

dojo.require("dojo.data.ItemFileWriteStore");
dojo.require("dojox.grid.DataGrid");
dojo.require("dojo.parser");
dojo.require("dijit.layout.ContentPane");
dojo.require("dijit.layout.BorderContainer");
dojo.require("dijit.form.Form");
dojo.require("dijit.form.TextBox");
dojo.require("dijit.form.ComboBox");
dojo.require("dijit.form.ComboBox");
dojo.require("dijit.form.Button");
dojo.require("dijit.Dialog");
dojo.require("dijit.ProgressBar");

dojo.addOnLoad(dojo_init);
dojo.addOnLoad(gmaps_init);

var topology;
var reservations;
var display_time;
var map;
var display_elements;
var gmaps_initialized = false;

var reservations_layout = [
        {name: 'Circuit ID', field: "id", width: "15em"},
        {name: 'Description', field: "description", width: "25em"},
        {name: 'User', field: "login", width: "8em"},
        {name: 'Status', field: "status", width: "8em"},
        {name: 'Start Time', field: "startTime", width: "10em", formatter: formatTime},
        {name: 'End Time', field: "endTime", width: "10em", formatter: formatTime}
];

function gmaps_init() {
        //console.log("gmaps_init()");

        //map = new GMap2(document.getElementById("map_div"), { size: new GSize({width:400,height:400}) });
        map = new GMap2(document.getElementById("map_div"));
        map.setCenter(new GLatLng(38, -97), 4);
        map.addControl(new GLargeMapControl());
        display_elements = new Array();

        display_time = new Date().getTime()/1000;

        gmaps_initialized = true;
        //console.log("gmaps_init(): return");

	// This is a trick to make sure when the google map resizes, that everything comes out properly
	map._lastCenter=map.getCenter(); 
	GEvent.addListener(map, 'moveend', function() { map._lastCenter=map.getCenter(); }); 
	GEvent.addListener(map, 'resize', function() { map.setCenter(map._lastCenter); }); 

        refresh_map();
}

function dojo_init() {
        console.log("dojo_init()");
        try {
            init_topology();
            init_reservations();
        } catch(e) {
            console.log("Error: "+e.message);
        }

        var filter_combo_id = dijit.byId('form_reservations_filter_identifier');
        dojo.connect(filter_combo_id, "onChange", function(){ filter_reservations(); });

        var filter_combo_desc = dijit.byId('form_reservations_filter_description');
        dojo.connect(filter_combo_desc, "onChange", function(){ filter_reservations(); });

        var filter_combo_user = dijit.byId('form_reservations_filter_user');
        dojo.connect(filter_combo_user, "onChange", function(){ filter_reservations(); });

        var filter_combo_status = dijit.byId('form_reservations_filter_status');
        dojo.connect(filter_combo_status, "onChange", function(){ filter_reservations(); });

        var select_reservation_button = dijit.byId('select_reservation_button');
        dojo.connect(select_reservation_button, "onClick", function(){ dijit.byId("dialog_find_reservations").show(); });

	dojo.byId('content_circuit_details').style.display    = 'none';
	dojo.byId('content_chart_frame').style.display    = 'none';
}

function draw_utilization_chart(response, reservation) {
        console.log("draw_utilization_chart()");

        reset_graph();

        try {
        var directions = [ "ingress", "egress" ];
        for (var i in directions) {
            var direction = directions[i];
            var store = response[direction];

            var data = new google.visualization.DataTable();

            data.addColumn('date', 'Time');
            data.addColumn('number', "In");
            data.addColumn('number', "Out");

            //console.log("draw_utilization_chart(): data table");

            //console.log("draw_utilization_chart(): store length: "+store.length);

            for(var i = 0; i < store.length; i++) {
                //console.log("draw_utilization_chart(): handling store "+i);

                var ts = new Date();
                ts.setTime(store[i]["time"] * 1000);

                //console.log("draw_utilization_chart(): allocated time: "+store[i]["time"]);

                //console.log("draw_utilization_chart(): row(in): "+store[i]["in"]);
                //console.log("draw_utilization_chart(): row(out): "+store[i]["out"]);

                var i = data.addRow();

                //console.log("draw_utilization_chart(): Added blank row");

                data.setCell(i, 0, ts);
                //console.log("draw_utilization_chart(): Added ts");
                data.setCell(i, 1, store[i]["in"]*8/1000/1000);
                //console.log("draw_utilization_chart(): Added in");
                data.setCell(i, 2, store[i]["out"]*8/1000/1000);
                //console.log("draw_utilization_chart(): Added out");

                //console.log("Adding "+store[i]["time"]);
            }

            chart_div = document.getElementById(direction+'_chart_div');

	    direction = (direction == "ingress")?"Ingress":"Egress";

            var chart = new google.visualization.AreaChart(chart_div);
            chart.draw(data, {width: 400, height: 180, legend: 'bottom', title: direction+' Circuit Utilization (Mbps)', max: reservation["bandwidth"] });
           // console.log("Drawing: "+direction);
        }
        } catch (e) {
                console.log("Error: "+e.message);
        }
       // console.log("draw_utilization_chart(): return");
}

function refresh_map() {
    console.log("refresh_map()");
    if (!topology) {
        console.log("refresh_map(): return");
        console.log("No topology");
        return;
    }

    if (!reservations) {
        console.log("refresh_map(): return");
        console.log("No reservations");
        return;
    }

    clear_map();
    reset_topology();
    fill_reservations();
    display_map();

    //console.log("refresh_map(): return");
}

function clear_map() {
    //console.log("clear_map()");
    map.clearOverlays();
    display_elements = new Array();
    //console.log("clear_map(): return");
}

function display_map() {
    //console.log("display_map()");
  for( var elm_id in topology) {
     if (topology[elm_id]['type'] != "node") {
        continue;
     }

     var node = topology[elm_id];

     if (node["latitude"] == null || node["longitude"] == null) {
        continue;
     }

     var location = new GLatLng(node["latitude"],node["longitude"]);
     var marker = new GMarker(location);
     marker.value = node;
     map.addOverlay(marker);
     display_elements[node["id"]] = marker;

     GEvent.addListener(marker, "click", function(latlng) {
                var node = this.value;

                var host_html = "";
                host_html += "Switch: "+node["name"]+"<br>";

                var tab1 = new GInfoWindowTab("Host Information", host_html);

                var tabs = [tab1];

                map.openInfoWindowTabsHtml(latlng, tabs);
             });
  }

  for( var elm_id in topology) {
      //console.log("Element: "+elm_id);

     if (topology[elm_id]['type'] != "link") {
        //console.log("Element not link: "+elm_id);
        continue;
     }

     var link = topology[elm_id];

     //console.log("Handling link: "+elm_id);

     if (link["remote_node_id"] == null) {
         //console.log("Link: "+elm_id+" has empty remote node id");
         continue;
     }

     if (display_elements[link["remote_node_id"]] == null) {
         //console.log("Link: "+elm_id+" has no remote node id");
         continue;
     }

     //console.log("Link: "+elm_id+" Node: "+link["remote_node_id"]);

     var color;

     var percentage = (link["used_capacity"]/link["reservable_capacity"]);
     if (percentage <= 0.25) {
         color = "#00FF00";
     } else if (percentage <= 0.50) {
         color = "#0000FF";
     } else if (percentage <= 0.75) {
         color = "#FFFF00";
     } else {
         color = "#FF0000";
     }

     //console.log("Used Bandwidth: "+ link["used_capacity"]);
     //console.log("Reservable Bandwidth: "+ link["reservable_capacity"]);
     //console.log("Percentage: "+percentage);

     var location_src = display_elements[topology[link["parent"]]["parent"]].getLatLng();
     var location_dst = display_elements[link["remote_node_id"]].getLatLng();

     var line = new GPolyline([ location_src, location_dst ], color, 3);
     line.value = link;
     map.addOverlay(line);

     //console.log("About to add listener");
     GEvent.addListener(line, "click", function(latlng) {
             var link = this.value;

	     var parent_node = topology[topology[link["parent"]]["parent"]];

             var link_html = "";
             link_html += "Source: "+parent_node["name"]+"<br>";
             link_html += "Destination: "+topology[link["remote_node_id"]]["name"]+"<br>";
             link_html += "Bandwidth: "+link["capacity"]/1000/1000+"M<br>";
             link_html += "Available Bandwidth: "+(link["capacity"]-link["used_capacity"])/1000/1000+"M<br>";

             var tab1 = new GInfoWindowTab("Link Information", link_html);

             var tabs = [tab1];

             map.openInfoWindowTabsHtml(latlng, tabs);
             });
     //console.log("Added listener");

     display_elements[link["id"]] = line;
  }
  //console.log("display_map(): return");
}

function fill_reservations() {
  //console.log("fill_reservations()");

  for( var reservation_id in reservations) {
     var reservation = reservations[reservation_id];

     if (reservation["status"] != "ACTIVE") {
        //console.log("Skipping "+reservation["id"]);
        continue;
     }

     console.log("Handling "+reservation["id"]);

     for( var link in reservation["local_path"] ) {
        var link_id = reservation["local_path"][link];

        if (!topology[link_id]) {
            console.log("Skipping link id: "+link_id);
            continue;
        }
        topology[link_id]["used_capacity"] += (reservation["bandwidth"] * 1000 * 1000);

        console.log("Used capacity on "+link_id+": "+topology[link_id]["used_capacity"]);

        if (!topology[link_id]["reservations"]) {
            topology[link_id]["reservations"] = new Array();
        }
        topology[link_id]["reservations"].push(reservation["id"]);
     }
  }

  //console.log("Added reservation information to topology");
  //console.log("Added reservations to data store");

  //console.log("fill_reservations(): return");
}

function reservations_grid_row_select(evt) {
    //console.log("reservations_grid_row_select()");

    var grid = dijit.byId("reservations.grid");
    var item = evt.grid.selection.getFirstSelected();
    var reservation_id = grid.store.getValues(item, "id");

    hideErrorDiv();

    show_reservation(reservation_id);

    dojo.byId('content_circuit_details').style.display    = '';
    dijit.byId('dialog_find_reservations').hide();

    dojo.byId('content_map_frame').style.height="380px";
    dojo.byId('content_map_frame').style.width="400px";
    dojo.byId('content_chart_frame').style.display    = '';

    map.setCenter(new GLatLng(38, -97), 3);

    map.checkResize();
    //console.log("reservations_grid_row_select(): return");
}

function show_reservation(reservation_id) {
    //console.log("show_reservation()");

    var elements_to_display = new Array();

    reset_graph();

    var reservation;
    for ( var resv_num in reservations ) {
        if (reservations[resv_num]['id'] == reservation_id) {
            reservation = reservations[resv_num];
            break;
        }
    }

    dojo.byId("details.circuit_id").innerHTML = reservation["id"];
    dojo.byId("details.description").innerHTML = reservation["description"];
    dojo.byId("details.status").innerHTML = reservation["status"];
    dojo.byId("details.user").innerHTML = reservation["login"];
    dojo.byId("details.start_time").innerHTML = formatTime(reservation["startTime"]);
    dojo.byId("details.end_time").innerHTML = formatTime(reservation["endTime"]);
    dojo.byId("details.bandwidth").innerHTML = reservation["bandwidth"]+"M";

    var ingress;
    if (reservation["local_source"] == null) {
        ingress = "Unknown";
    } else if (topology[reservation["local_source"]] == null) {
        ingress = reservation["local_source"];
    } else {
        var source_link = topology[reservation["local_source"]];
        var source_port = topology[source_link["parent"]];
        var source_node = topology[source_port["parent"]];
        ingress = source_node["name"];
        if (source_port["name"]) {
            ingress += ":"+source_port["name"];
        }
    }

    var egress;
    if (reservation["local_destination"] == null) {
        egress = "Unknown";
    } else if (topology[reservation["local_destination"]] == null) {
        egress = reservation["local_destination"];
    } else {
        var dest_link = topology[reservation["local_destination"]];
        var dest_port = topology[dest_link["parent"]];
        var dest_node = topology[dest_port["parent"]];
        egress = dest_node["name"];
        if (dest_port["name"]) {
            egress += ":"+dest_port["name"];
        }
    }

    dojo.byId("details.ingress").innerHTML = ingress;
    dojo.byId("details.egress").innerHTML = egress;

    var path = "";
    for ( var link_num in reservation["local_path"] ) {
        var link_id = reservation["local_path"][link_num];
        var parent_port = topology[topology[link_id]["parent"]];
        var parent_node = topology[parent_port["parent"]];

        var current_point = parent_node["name"];
        if (parent_port["name"]) {
            current_point += ":"+parent_port["name"];
        } else {
            var id = parent_port['id'];
            id = id.replace(/.*:port=/, '');
            current_point += ":"+id;
        }

        path += current_point+"<br>";
    }

    dojo.byId("details.local_path").innerHTML = path;

    for ( var link_num in reservation["local_path"] ) {
        var link_id = reservation["local_path"][link_num];

        var link = topology[link_id];
        if (link) {
            //console.log("Adding "+link_id+" to show list");
            elements_to_display[link_id] = true;

            elements_to_display[topology[link["parent"]]["parent"]] = true;
            elements_to_display[topology[link["remote_node"]]] = true;
            //console.log("Adding "+topology[link["parent"]]["parent"]+" to show list");
            //console.log("Adding "+link["remote_node"]+" to show list");
        }
    }

    for (var element_id in display_elements) {
        if (!elements_to_display[element_id]) {
            //console.log("Hiding "+element_id);
            map.removeOverlay(display_elements[element_id]);
        } else {
            //console.log("Showing "+element_id);
            map.addOverlay(display_elements[element_id]);
        }
    }
    
    dijit.byId('dialog_loading_circuit_stats').show();

    dojo.xhrGet ({ 
            url: "status.cgi",
            handleAs: "json",
            content: { 'function': "get_circuit_statistics", 'reservation_id': reservation["id"] },
            timeout: 15000,
            load: function(response, io_args) { dijit.byId('dialog_loading_circuit_stats').hide(); draw_utilization_chart(response, io_args); },
	    error: function (response, io_args) { dijit.byId('dialog_loading_circuit_stats').hide(); showErrorDiv("Problem loading circuit statistics"); },
            mimetype: "text/json" 
        });

    //console.log("show_reservation(): return");
}

function reset_graph() {
    // get rid of existing graphs
    var directions = [ "ingress", "egress" ];
    for (var i in directions) {
        var chart_div = dojo.byId(directions[i]+"_chart_div");
        while (chart_div.hasChildNodes()) {
            chart_div.removeChild(chart_div.lastChild);
        }
    }
}

function reset_topology() {
    //console.log("reset_topology()");
    for( var elm_id in topology) {
        var elm = topology[elm_id];

        if (elm["type"] != "link")
                continue;

        elm["used_capacity"] = 0;
        elm["reservations"] = null;
    }
    //console.log("reset_topology(): return");
}

function init_topology(status) {
    dojo.xhrGet ({ 
            url: "status.cgi",
            content: { 'function': "get_topology" },
            timeout: 15000,
            handleAs: "json",
            load: handle_init_topology_response,
            error: function (response, io_args) { showErrorDiv("Problem loading domain topology") },
            mimetype: "text/json" 
            });
}

function handle_init_topology_response(response, io_args) {
    console.log("handle_init_topology_response()");

    topology = response;
    refresh_map();
}

function init_reservations(status) {
    dojo.xhrGet ({
            url: "status.cgi",
            content: { 'function': "get_reservations" },
            timeout: 15000,
            handleAs: "json",
            load: handle_init_reservations_response,
            error: function (response, io_args) { showErrorDiv("Problem loading reservation list") },
            mimetype: "text/json" 
            });
}

function handle_init_reservations_response(response, io_args) {
    console.log("handle_init_reservations_response()");

    var arr = new Array();
    for( var reservation_id in response) {
        if (response[reservation_id]["status"] != "ACTIVE")
                continue;

        arr.push(response[reservation_id]);
    }
    var data = {
            identifier: 'id',
            label: 'id',
            items: arr,
    };

    var store = new dojo.data.ItemFileWriteStore({data: data});
    var grid = dijit.byId("reservations.grid");
    grid.setStore(store);

    dojo.connect(grid, "onRowClick", reservations_grid_row_select);

    reservations = response;
    refresh_map();
}

function filter_reservations() {
    dojo.xhrGet ({
            url: "status.cgi",
            content: { 'function': "get_reservations" },
            timeout: 15000,
            form: dojo.byId('form_reservations_filter'),
            handleAs: "json",
            load: handle_filter_reservations_response,
            error: function (response, io_args) { showErrorDiv("Problem loading reservation list") },
            mimetype: "text/json" 
            });
}

function handle_filter_reservations_response(response, io_args) {
  var arr = new Array();
  for( var reservation_id in response) {
        arr.push(response[reservation_id]);
  }
  var data = {
            identifier: 'id',
            label: 'id',
            items: arr,
  };

  var store = new dojo.data.ItemFileWriteStore({data: data});
  var grid = dijit.byId("reservations.grid");
  grid.setStore(store);

  // This needs to be done to recenter the dialog
  dijit.byId("dialog_find_reservations")._position();
}

function formatTime(value){
    var ts = new Date();
    ts.setTime(value * 1000);

    var string;
    
    try {
        string = ts.format("yyyy-mm-dd HH:MM");
    } catch (e) {
        string = ts.getFullYear()+"-"+(ts.getMonth()+1)+"-"+ts.getDate()+" "+ts.getHours()+":"+ts.getMinutes();
    }

    return string;
}

function showErrorDiv(msg){
	hideErrorDiv();
	dojo.place('<div id="errorDiv"><div class="errorTop">&nbsp;</div>'+msg+'</div>', dojo.byId('content'), "first");
}

function hideErrorDiv(){
	if(dojo.byId('errorDiv') != null){
		dojo.destroy(dojo.byId('errorDiv'));
	}
}
