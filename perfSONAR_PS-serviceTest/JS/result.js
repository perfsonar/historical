var owampTableHeadings = ["Source","Destination","Bidirectional","Forward&nbsp;Direction&nbsp;Loss (Past&nbsp;30&nbsp;minutes)","Reverse&nbsp;Direction&nbsp;Loss (Past&nbsp;30&nbsp;minutes)","Graph"];
var bwctlTableHeadings = ["Source","Destination","Bidirectional","Protocol","Duration","1 week Avg Throughput Src-Dst (Gbps)","1 week Avg Throughput Dst-Src (Gbps)","Graph"];
var allTests = new Array();
// draws the result table
function drawTable(evtType){
		for (var i=0;i<divLayers.length;i++){
			var testDiv = document.getElementById(divLayers[i]);
			var myTable = document.createElement("table");
			var tableName = "table"+divLayers[i];
			myTable.id = tableName;
			myTable.border=1;
			myTable.className="basic_table";
			myTable.width = "700px";
			testDiv.appendChild(myTable);
			var newTR = document.createElement("tr");
			myTable.appendChild(newTR);
			if((evtType == "http://ggf.org/ns/nmwg/tools/iperf/2.0") || (evtType == "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0")){
				for (var j=0;j<bwctlTableHeadings.length;j++){
					var tmpTD = document.createElement("th");
					tmpTD.align="center";	
					if(j < bwctlTableHeadings.length-1){
						tmpTD.setAttribute('onclick',"return sortTable('"+tableName+"',"+j+",true);");
			                        tmpTD.setAttribute('onmouseover',"return changeMousePointer(this)");
					}
					
					tmpTD.innerHTML =bwctlTableHeadings[j]+" <img id=\""+tableName+j+"\" src=\"images/uparrow.png\" align=\"right\" width=\"9px\" height=\"9px\" style=\"display:none\"/>";
					newTR.appendChild(tmpTD);
				}
			}else if((evtType == "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921") || (evtType == "http://ggf.org/ns/nmwg/tools/owamp/2.0")){
				for (var j=0;j<owampTableHeadings.length;j++){
					var tmpTD = document.createElement("th");
					tmpTD.align="center";
					if(j < owampTableHeadings.length-1){
                                                tmpTD.setAttribute('onclick',"return sortTable('"+tableName+"',"+j+",true);");
                                                tmpTD.setAttribute('onmouseover',"return changeMousePointer(this)");					
					}
                                        tmpTD.innerHTML =owampTableHeadings[j]+"<img id=\""+tableName+j+"\" src=\"images/uparrow.png\" align=\"right\" width=\"9px\" height=\"9px\" style=\"display:none\"/>";
					newTR.appendChild(tmpTD);
				}		
			}
			
		toggleSortArrowSymbols(tableName,0,true);	
		}

						
}

//fills the table with entries
function updateTable(data,testType,evtType){
	table = document.getElementById("table"+testType);
	var parsedData = eval("(" + data + ")");
	allTests[testType] = new Array();
	var tmpDir = parsedData[testType];
	for (var testKey in tmpDir){
		allTests[testType][testKey] = tmpDir[testKey];
		var tmpTR = document.createElement("tr");
		var testDetails = tmpDir[testKey];
				
		var srcTD = document.createElement("td");
	 	srcTD.innerHTML = '<span style="white-space: nowrap;">'+testDetails['src']+'</span>';
  		srcTD.innerHTML += " ("+testDetails['srcIP']+")";
		srcTD.align="center";
		srcList[testDetails['src']]=1;
		allHostsList[testDetails['src']]=1;
		tmpTR.appendChild(srcTD);
				
		var dstTD = document.createElement("td");
		dstTD.innerHTML = '<span style="white-space: nowrap;">'+testDetails['dst']+'</span>';
                dstTD.innerHTML += " ("+testDetails['dstIP']+")";
		dstTD.align="center";
		srcList[testDetails['dst']]=1;
		allHostsList[testDetails['dst']]=1;	
		tmpTR.appendChild(dstTD);
				
  		var dirTD = document.createElement("td");
		dirTD.innerHTML = testDetails['bidirectional'];
		dirTD.align="center";
		tmpTR.appendChild(dirTD);
				
   		var graphTD = document.createElement("td");		
				
   		if((evtType == "http://ggf.org/ns/nmwg/tools/iperf/2.0") || (evtType == "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0")){	
           		var timeTD = document.createElement("td");
            		timeTD.innerHTML = testDetails['protocol'];
            		timeTD.align="center";
            		tmpTR.appendChild(timeTD);
            			
           		var protTD = document.createElement("td");
          		protTD.innerHTML = testDetails['timeDuration'];
            		protTD.align="center";
            		tmpTR.appendChild(protTD);
            			

                        var thptTD = document.createElement("td");
                        var thptVal = parseFloat(testDetails['data']['throughput']);
			console.log("data:"+thptVal);
			if(!isNaN(thptVal)){
                        	thptTD.innerHTML = Math.round((thptVal/(1000*1000*1000))*1000)/1000;
			}else{
                                thptTD.innerHTML = "No data";
                        }
			thptTD.align="center";
                        tmpTR.appendChild(thptTD);

                        var thptrTD = document.createElement("td");
                        var thptrVal = parseFloat(testDetails['dataR']['throughput']);
			console.log("dataR"+thptrVal);
			if(!isNaN(thptrVal)){
				
		        	thptrTD.innerHTML = Math.round((thptrVal/(1000*1000*1000))*1000)/1000;
                        }else{
                                thptrTD.innerHTML = "No data";
                        }
                        thptrTD.align="center";
                        tmpTR.appendChild(thptrTD);


            		graphTD.innerHTML = "<select type=\"button\" onChange=getGraphURL(\""+testType+"\",\""+testKey+"\",options[selectedIndex].value)> <option value=\"\"> Select </option> <option value=\"2592000\"> 1 month </option> <option value=\"7776000\"> 3 months </option> </select>";
   		}else if((evtType == "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921") || (evtType == "http://ggf.org/ns/nmwg/tools/owamp/2.0")){
           		var fLossTD = document.createElement("td");
           		if (testType=="Active"){	
            			fLossTD.innerHTML = testDetails['data']['loss'];          	
                	}else{
                		fLossTD.innerHTML = "*";
                	}
           		fLossTD.align="center";
           		tmpTR.appendChild(fLossTD);

            		var rLossTD = document.createElement("td");
            		if (testDetails['bidirectional'] == "Yes" && testType=="Active"){	
            			rLossTD.innerHTML = testDetails['dataR']['loss'];          	
                	}else{
                		rLossTD.innerHTML = "*";
                	}
            		rLossTD.align="center";
            		tmpTR.appendChild(rLossTD);
 
            		var graphTD = document.createElement("td"); 
            		graphTD.innerHTML = "<select type=\"button\" onchange=getGraphURL(\""+testType+"\",\""+testKey+"\",options[selectedIndex].value)> <option value=\"\"> Select </option> <option value=\"14400\"> 4 hours </option> <option value=\"43200\"> 12 hours </option> <option value=\"86400\">1 Day</option> <option value=\"604800\"> 1 week</option> </select>";
            		graphTD.align="center";			
            		
        	}
   				
   		graphTD.align="center";
   		tmpTR.appendChild(graphTD);
   		table.appendChild(tmpTR);
	}
	
}


function getGraphURL(testType,testKey,timeRange){
	if(timeRange != ""){
		console.log(timeRange);
		var graphHttp = createRequestObject();
        	var queryparams = "ma_url="+queryParameters["ma_url"];
        	var endpoints = "srcRaw="+allTests[testType][testKey]["srcRaw"]+"&dstRaw="+allTests[testType][testKey]["dstRaw"];
        	var params;
        	var eventType;
        	if((queryParameters["eventType"] == "http://ggf.org/ns/nmwg/tools/iperf/2.0") || (queryParameters["eventType"] == "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0")){
                	params="protocol="+allTests[testType][testKey]["protocol"]+"&timeDuration="+allTests[testType][testKey]["timeDuration"];
                	eventType = "eventType="+queryParameters["eventType"];
        	}else if((queryParameters["eventType"] == "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921") || (queryParameters["eventType"] == "http://ggf.org/ns/nmwg/tools/owamp/2.0")){
                	params="count="+allTests[testType][testKey]["count"]+"&bucket_width="+allTests[testType][testKey]["bucket_width"];
                	//use the other eventType to get buckets
                	eventType = "eventType=http://ggf.org/ns/nmwg/characteristic/delay/summary/20110317";
        	}
        	graphHttp.open('get','./metaKeyReq.cgi?nocache='+Math.random()+"&"+queryparams+"&"+eventType+"&"+endpoints+"&"+params, false);
        	graphHttp.send(null);
        	if(graphHttp.status == 200){
              		var graphHttpResponse = graphHttp.responseText;
              		var maKeyJson = eval("(" + graphHttpResponse + ")");
              		var link;
              		if((queryParameters["eventType"] == "http://ggf.org/ns/nmwg/tools/iperf/2.0") || (queryParameters["eventType"] == "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0")){
                     		link = "./bandwidthGraph.cgi?url="+maKeyJson["ma_url"]+"&key="+maKeyJson["maKey"]+"&keyR="+maKeyJson["maKeyR"]+"&dstIP="+maKeyJson["dstIP"]+"&srcIP="+maKeyJson["srcIP"]+"&dst="+maKeyJson["dst"]+"&src="+maKeyJson["src"]+"&type=TCP&length="+timeRange;
                     		var  graphWindow = window.open(link,Math.random(),'height=800,width=1200,scrollbars=1,toolbar=1');
              	}else if((queryParameters["eventType"] == "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921") || (queryParameters["eventType"] == "http://ggf.org/ns/nmwg/tools/owamp/2.0")){
                	     link = "./delayGraph.cgi?url="+maKeyJson["ma_url"]+"&key="+maKeyJson["maKey"]+"&keyR="+maKeyJson["maKeyR"]+"&dstIP="+maKeyJson["dstIP"]+"&srcIP="+maKeyJson["srcIP"]+"&dst="+maKeyJson["dst"]+"&src="+maKeyJson["src"]+"&type=TCP&length="+timeRange;
                     		var  graphWindow = window.open(link,Math.random(),'height=800,width=1200,scrollbars=1,toolbar=1');
             	 }
        	}
	}
}

