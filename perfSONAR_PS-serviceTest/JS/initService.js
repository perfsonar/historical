var divLayers = ["Active","Inactive"];
var queryParameters = new Array();

function createRequestObject() { 
	var req; 
  	if (window.XMLHttpRequest) { // Firefox, Safari, Opera... 
  		req = new XMLHttpRequest(); 
  	} else if (window.ActiveXObject) { // Internet Explorer 5+ 
    	req = new ActiveXObject("Microsoft.XMLHTTP"); 
  	} else { 
    	alert('There was a problem creating the XMLHttpRequest object'); 
    	req = '';
  	}		
  return req; 
} 
     
// Make the XMLHttpRequest object 
var http = createRequestObject(); 

function processSelectedRadioOption(hostValue,serviceType){
	clearpage();
	sendRequest(hostValue,serviceType);
}	

function sendRequest(ma_url,eventType) { 
  	var now = new Date();
  	if(ma_url === "" || eventType === ""){
	  	var testparamdiv = document.getElementById("testParametersDiv");
	  	var htmltext = "<br><br><h3> Error!Empty parameters";
	  	testparamdiv.innerHTML = htmltext;
	  
  	}else{
	  	http = createRequestObject();
	  	http.open('get', 'getData.cgi?ma_url='+ma_url+'&eventType='+eventType+'&nocache='+now.getTime());
	  	queryParameters["ma_url"] = ma_url;
	 	queryParameters["eventType"] = eventType;
	  	document.getElementById("testParametersDiv").innerHTML = "<ul><li>MA_URL: "+ma_url+"</li></br><li>Service Test URL: "+eventType+"</li></ul>";
	  	drawTable(eventType);
	  	http.onreadystatechange = handleResponse; 
	  	http.send(null); 
	  	setprogressTimerID = setInterval("setProgress()",200);
	  	clearprogressTimerID = setInterval("blinkProgressDots()",400);
  	}
}	 
     
function handleResponse() { 
  	if(http.readyState == 4 && http.status == 200){ 
   		response = http.responseText; // Text returned FROM perl script
    	var eType = queryParameters["eventType"]; 
    	if(response) {  
        	JSONData = eval("(" + response + ")");
        	updateTable(response,"Active",eType);
        	updateTable(response,"Inactive",eType);
      		clearInterval(setprogressTimerID);
      		clearInterval(clearprogressTimerID);
      		clearProgress();
      		createDataDisplayDiv(eType);
    	}			 
  	}else if(http.status != 200){
	  	var testparamdiv = document.getElementById("testParametersDiv");
	  	var htmltext = "<br><br><h1> Error!!!Could not retrieve data from MA!!";
	  	testparamdiv.innerHTML = htmltext;
      	clearInterval(setprogressTimerID);
     	clearInterval(clearprogressTimerID);
      	clearProgress();
  	} 
}

//comes here once the user selects MA and clicks the button
function doclick(selectboxname, eventType) {
		clearpage();
		var selectbox = document.getElementById(selectboxname);
		ma_url = selectbox.options[selectbox.selectedIndex].value;
		var regex = /\<|\>|\#|\$|\%|\!|\(|\)|\[|\]|\*/g;
		if (ma_url.match(regex) || eventType.match(regex)){
  		var testparamdiv = document.getElementById("testParametersDiv");
  		var htmltext = "<br><br><h3> Invalid parameters!!";
  		testparamdiv.innerHTML = htmltext;
		}else{
  		sendRequest(ma_url,eventType);
		}

		return true;
}


function setProgress(){
        document.getElementById("Progress").style.display = "block";
	document.getElementById("Progress").innerHTML="Retrieving data...";
}

function blinkProgressDots(){
	document.getElementById("Progress").innerHTML="Retrieving data";
}

function clearProgress(){
        document.getElementById("Progress").display = "none";
	document.getElementById("Progress").innerHTML=" ";
}

function clearpage(){
	srcList = new Array();
 	dstList= new Array();
 	allHostsList= new Array();
 	queryParameters = new Array();
 	allTests = new Array();
	for (var i=0;i<divLayers.length;i++){
		var mytable = document.getElementById("table"+divLayers[i]);
		if(mytable != null){
			document.getElementById(divLayers[i]).removeChild(mytable);
		}	
	}

	var datadiv = document.getElementById("datadisplay");
	datadiv.style.visibility='hidden';
	datadiv.innerHTML=" ";
}

//displays the test groups in the menu
function showTestGroups(){
	for (var i=0; i < document.input.servicetype.length; i++){
   		if (document.input.servicetype[i].checked){
      			var rad_val = document.input.servicetype[i].value;
      			toggle_visibility(rad_val,true);
    		}else{
    			var rad_val = document.input.servicetype[i].value;
	        	toggle_visibility(rad_val,false);
    		}
		}


}

function toggle_visibility(className,show) {
	var e = document.getElementById(className);
		if(show){
			e.style.display = "block";
		}else{
			e.style.display = "none";
		}
}