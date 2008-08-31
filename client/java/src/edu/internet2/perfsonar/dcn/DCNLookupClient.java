package edu.internet2.perfsonar.dcn;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import org.apache.commons.httpclient.HttpException;
import org.apache.log4j.Logger;
import org.jdom.Element;

import edu.internet2.perfsonar.PSException;
import edu.internet2.perfsonar.PSLookupClient;

/**
 * Performs lookup operations useful for dynamic circuits netwoking (DCN)
 * applications.
 *
 */
public class DCNLookupClient{
	private Logger log;
	private String[] gLSList;
	private String[] hLSList;
	private boolean tryAllGlobal;
	
	private String REQUEST = "<nmwg:metadata id=\"meta1\">" +
		"<xquery:subject id=\"sub1\">" +
		"<!--xquery-->" +
		"</xquery:subject>" +
		"<nmwg:eventType>http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0</nmwg:eventType>" +
		"<xquery:parameters id=\"param1\">" +
		"<nmwg:parameter name=\"lsOutput\">native</nmwg:parameter>" +
		"</xquery:parameters>" +
		"</nmwg:metadata>" +
		"<nmwg:data metadataIdRef=\"meta1\" id=\"data1\"/>";
	private String HOST_DISC_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\";\n" +
		"declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n" +
		"declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"for $metadata in /nmwg:store[@type=\"LSStore\"]/nmwg:metadata\n" +
		"    let $metadata_id := $metadata/@id  \n" +
		"    let $data := /nmwg:store[@type=\"LSStore\"]/nmwg:data[@metadataIdRef=$metadata_id]\n" +
		"    where $data/nmwg:metadata/nmwg:eventType[text()=\"http://oscars.es.net/OSCARS\"] and $data/nmwg:metadata/summary:subject/nmtb:domain/nmtb:name[@type=\"dns\" and text()=\"<!--domain-->\"]\n" +
		"    return $metadata/perfsonar:subject/psservice:service/psservice:accessPoint\n";
	
	private String HOST_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"/nmwg:store[@type=\"LSStore\"]/nmwg:data/nmwg:metadata/*[local-name()=\"subject\"]/nmtb:node/nmtb:relation/nmtb:linkIdRef/text()[../../../nmtb:address[text()=\"<!--hostname-->\"]]\n";
	
	/**
	 * Creates a new client with the list of Global lookup services to 
	 * contact determined by reading the hints file at the provided URL.
	 * The result returned by the list file will be randomly re-ordered.
	 * 
	 * @param hintsFile the URL of the hints file to use to populate the list of global lookup services
	 * @throws HttpException
	 * @throws IOException
	 */
	public DCNLookupClient(String hintsFile) throws HttpException, IOException {
		this.log = Logger.getLogger(this.getClass());
		String[] gLSList = PSLookupClient.getGlobalHints(hintsFile, true);
		this.gLSList = gLSList;
		this.hLSList = null;
		this.tryAllGlobal = false;
	}
	
	/**
	 * Creates a new client that uses the explicitly set list of global lookup
	 * services. 
	 * 
	 * @param gLSList
	 */
	public DCNLookupClient(String[] gLSList){
		this.log = Logger.getLogger(this.getClass());
		this.gLSList = gLSList;
		this.hLSList = null;
		this.tryAllGlobal = false;
	}

	/**
	 * Creates a new client with an explicitly set list of global and/or
	 * home lookup services. One of the parameters may be null. If the first 
	 * parameter is null then no global lookup servioces will be contacted
	 * only the given home lookup services will be used. If the second paramter is
	 * null the given set of global lookup services will be used to find the home
	 * lookup service.
	 * 
	 * @param gLSList the list of global lookup services to use
	 * @param hLSList the list of home lookup services to use
	 */
	public DCNLookupClient(String[] gLSList, String[] hLSList){
		this.log = Logger.getLogger(this.getClass());
		this.gLSList = gLSList;
		this.hLSList = hLSList;
		this.tryAllGlobal = false;
	}
	
	/**
	 * Finds the URN of a host with the given name. 
	 * 
	 * @param name the name of the host o lookup
	 * @return the URN of the host with the given name
	 * @throws PSException
	 */
	public String lookupHost(String name) throws PSException{
		String urn = null;
		String[] hLSMatches = this.hLSList;
		if(hLSList == null){
			String discoveryReq = REQUEST;
			String discoveryXQuery = HOST_DISC_XQUERY;
			String domain = name.replaceFirst("(.+\\.)?", "");
			discoveryXQuery = discoveryXQuery.replaceAll("<!--domain-->", domain);
			discoveryReq = discoveryReq.replaceAll("<!--xquery-->", discoveryXQuery.replaceAll("[\\$]", "\\\\\\$"));
			hLSMatches = this.discover(discoveryReq);
		}
		
        String request = REQUEST;
        String xquery = HOST_XQUERY;
        xquery = xquery.replaceAll("<!--hostname-->", name);
        request = request.replaceAll("<!--xquery-->", xquery);
        for(String hLS : hLSMatches){
        	this.log.info("hLS: " + hLS);
        	PSLookupClient lsClient = new PSLookupClient(hLS);
        	Element response = lsClient.query(request);
        	Element datum = lsClient.parseDatum(response, lsClient.getPsServiceNs());
        	if(datum != null && urn != datum.getText()){
        		urn = datum.getText();
        		break;
        	}
        }
        
        return urn;
	}
	
	/**
	 * Contacts a global lookup service(s) to get the list of home lookup
	 * services possible containing desired data. If the "tryAllGlobals"
	 * property is set to true then it will contact every global to build
	 * its list of home lookup services.
	 * 
	 * @param request the discovery request
	 * @return the list of matching home lookup services
	 * @throws PSException
	 */
	public String[] discover(String request) throws PSException{
		String[] accessPoints = null;
		HashMap<String, Boolean> apMap = new HashMap<String, Boolean>();
		
		int attempts = (this.tryAllGlobal ? gLSList.length : 1);
		String errLog = "";
		for(int a = 0; a < attempts; a++){
			try{
				PSLookupClient lsClient = new PSLookupClient(this.gLSList[a]);
		        Element response = lsClient.query(request);
		        Element metaData = response.getChild("metadata", lsClient.getNmwgNs());
		        
		        if(metaData == null){
		        	throw new PSException("No metadata element in discovery response");
		        }
		        Element eventType = metaData.getChild("eventType", lsClient.getNmwgNs());
		        if(eventType == null){
		        	throw new PSException("No eventType returned");
		        }else if(eventType.getText().startsWith("error.ls")){
		        	Element errDatum = lsClient.parseDatum(response, lsClient.getNmwgrNs());
		        	String errMsg = (errDatum == null ? "An unknown error occurred" : errDatum.getText());
		        	this.log.error(eventType.getText() + ": " + errMsg);
		        	throw new PSException("Global discovery error: " + errMsg);
		        }else if(!"success.ls.query".equals(eventType.getText())){
		        	throw new PSException("Hostname not found because lookup " +
		        						  "returned an unrecognized status");
		        }
		        
		        Element datum = lsClient.parseDatum(response, lsClient.getPsServiceNs());
		        if(datum == null){
		        	throw new PSException("No service datum returned from discovery request");
		        }
		        List<Element> accessPointElems = datum.getChildren("accessPoint", lsClient.getPsServiceNs());
		        for(int i = 0; i < accessPointElems.size(); i++){
		        	apMap.put(accessPointElems.get(i).getTextTrim(), true);
		        }
			}catch(PSException e){
				if(!this.tryAllGlobal){
					throw e;
				}else{
					errLog += this.gLSList[a] + ": " + e.getMessage() + "\n\n";
				}
			}catch(Exception e){
				if(!this.tryAllGlobal){
					throw new PSException(e);
				}else{
					errLog += this.gLSList[a] + ": " + e.getMessage() + "\n\n";
				}
			}
		}
		
		if(apMap.isEmpty()){
			throw new PSException("No home lookup services found after trying" +
					" multiple global services:\n" + errLog);
		}
		
		accessPoints = new String[apMap.size()];
		apMap.keySet().toArray(accessPoints);
		
		return accessPoints;
	}

	/**
	 * @return the list of global lookup services
	 */
	public String[] getGLSList() {
		return gLSList;
	}

	/**
	 * @param list the list of global lookup services to set
	 */
	public void setGLSList(String[] list) {
		gLSList = list;
	}

	/**
	 * @return the list of home lookup services
	 */
	public String[] getHLSList() {
		return hLSList;
	}

	/**
	 * @param list the list of home lookup services to set
	 */
	public void setHLSList(String[] list) {
		hLSList = list;
	}

	/**
	 * @return if true then every global lookup services will be used to
	 *  find the home LS, otherwise just the first entry will be used
	 */
	public boolean isTryAllGlobal() {
		return tryAllGlobal;
	}

	/**
	 * @param tryAllGlobal if true then every global lookup services will be used to
	 *  find the home LS, otherwise just the first entry will be used
	 */
	public void setTryAllGlobal(boolean tryAllGlobal) {
		this.tryAllGlobal = tryAllGlobal;
	}
}
