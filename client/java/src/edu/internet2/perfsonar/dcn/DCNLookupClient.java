package edu.internet2.perfsonar.dcn;

import java.io.IOException;
import java.io.StringWriter;
import java.util.HashMap;
import java.util.List;

import org.apache.commons.httpclient.HttpException;
import org.apache.log4j.Logger;
import org.jdom.Element;
import org.jdom.JDOMException;
import org.jdom.Namespace;
import org.jdom.output.XMLOutputter;
import org.jdom.xpath.XPath;

import edu.internet2.perfsonar.NodeRegistration;
import edu.internet2.perfsonar.PSException;
import edu.internet2.perfsonar.PSLookupClient;
import edu.internet2.perfsonar.PSNamespaces;
import edu.internet2.perfsonar.ServiceRegistration;

/**
 * Performs lookup operations useful for dynamic circuits networking (DCN)
 * applications.
 *
 */
public class DCNLookupClient{
	private Logger log;
	private String[] gLSList;
	private String[] hLSList;
	private boolean tryAllGlobal;
	private boolean useGlobalLS;
	private PSNamespaces psNS;
	
	static final public String IDC_SERVICE_TYPE = "IDC";
	static final public String PROTO_OSCARS = "http://oscars.es.net/OSCARS";
	static final public String PROTO_WSN = "http://docs.oasis-open.org/wsn/b-2";
	static final public String PARAM_SUPPORTED_MSG = "keyword:supportedMessage";
	static final public String PARAM_TOPIC = "keyword:topic";

	private String DISC_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\";\n" +
		"declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n" +
		"declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"for $metadata in /nmwg:store[@type=\"LSStore\"]/nmwg:metadata\n" +
		"    let $metadata_id := $metadata/@id  \n" +
		"    let $data := /nmwg:store[@type=\"LSStore\"]/nmwg:data[@metadataIdRef=$metadata_id]\n" +
		"    where $data/nmwg:metadata/nmwg:eventType[text()=\"http://oscars.es.net/OSCARS\"] and $data/nmwg:metadata/summary:subject/<!--addrPath-->[@type=\"<!--type-->\" and text()=\"<!--domain-->\"]\n" +
		"    return $metadata/perfsonar:subject/psservice:service/psservice:accessPoint\n";
	
	private String HOST_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"/nmwg:store[@type=\"LSStore\"]/nmwg:data/nmwg:metadata/*[local-name()=\"subject\"]/nmtb:node/nmtb:relation/nmtb:linkIdRef/text()[../../../nmtb:address[text()=\"<!--hostname-->\"]]\n";
	
	private String NODE_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"declare namespace nmtl3=\"http://ogf.org/schema/network/topology/l3/20070828/\";\n" +
		"/nmwg:store[@type=\"LSStore\"]/nmwg:metadata/*[local-name()=\"subject\"]/nmtb:node[./<!--type-->[text()=\"<!--addr-->\"]]\n";
	
	private String IDC_XQUERY = 
		"declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
		"declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
		"declare namespace dcn=\"http://ggf.org/ns/nmwg/tools/org/dcn/1.0/\";\n" +
		"for $metadata in /nmwg:store[@type=\"LSStore\"]/nmwg:metadata\n" +
		"    where $metadata/dcn:subject/nmtb:service/nmtb:type[text()=\"<!--type-->\"] and $metadata/dcn:subject/nmtb:service/nmtb:relation[@type=\"<!--relation-->\"]/nmtb:<!--idType-->[text()=\"<!--id-->\"]\n" +
		"    return $metadata/dcn:subject/nmtb:service<!--xpath-->\n";
	
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
		this.useGlobalLS = true;
		this.psNS = new PSNamespaces();
	}
	
	/**
	 * Creates a new client with the list of Global lookup services to 
	 * contact determined by reading the hints file at the provided URL.
	 * The result returned by the list file will be randomly re-ordered.
	 * All registration requests will use the home lookup services listed
	 * in the second parameter
	 * 
	 * @param hintsFile the URL of the hints file to use to populate the list of global lookup services
	 * @param hLSList the list of home lookup services to which to send register requests
	 * @throws HttpException
	 * @throws IOException
	 */
	public DCNLookupClient(String hintsFile, String[] hLSList) throws HttpException, IOException {
		this.log = Logger.getLogger(this.getClass());
		String[] gLSList = PSLookupClient.getGlobalHints(hintsFile, true);
		this.gLSList = gLSList;
		this.hLSList = hLSList;
		this.tryAllGlobal = false;
		this.useGlobalLS = true;
		this.psNS = new PSNamespaces();
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
		this.psNS = new PSNamespaces();
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
		this.psNS = new PSNamespaces();
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
		if(useGlobalLS || hLSList == null){
			String discoveryXQuery = DISC_XQUERY;
			String domain = name.replaceFirst(".+?\\.", "");
			discoveryXQuery = discoveryXQuery.replaceAll("<!--addrPath-->", "nmtb:domain/nmtb:name");
			discoveryXQuery = discoveryXQuery.replaceAll("<!--domain-->", domain);
			discoveryXQuery = discoveryXQuery.replaceAll("<!--type-->", "dns");
			Element discReqElem = this.createQueryMetaData(discoveryXQuery);
			hLSMatches = this.discover(this.requestString(discReqElem, null));
		}
		
        String xquery = HOST_XQUERY;
        xquery = xquery.replaceAll("<!--hostname-->", name);
        Element reqElem = this.createQueryMetaData(xquery);
        String request = this.requestString(reqElem, null);
        for(String hLS : hLSMatches){
        	this.log.info("hLS: " + hLS);
        	PSLookupClient lsClient = new PSLookupClient(hLS);
        	Element response = lsClient.query(request);
        	Element datum = lsClient.parseDatum(response, psNS.PS_SERVICE);
        	if(datum != null && urn != datum.getText()){
        		urn = datum.getText();
        		break;
        	}
        }
        
        return urn;
	}
	
	/**
	 * Finds the URN of a host with the given name. 
	 * 
	 * @param name the name of the host o lookup
	 * @return the nmtb:node element
	 * @throws PSException
	 */
	public Element lookupNode(String addr) throws PSException{
		Element node = null;
		String[] hLSMatches = this.hLSList;
		
		String addrPath = "nmtl3:network/nmtl3:subnet/nmtl3:address";
		String type = "nmtl3:port/nmtl3:address";
		String typeAttr = "ipv4";
		String domain = addr;
        if(addr.matches(".*\\.[a-zA-Z]+.*")){
        	type = "nmtb:name";
        	addrPath = "nmtb:domain/nmtb:name";
        	typeAttr = "dns";
        	domain = domain.replaceFirst(".+?\\.", "");
        }
		if(useGlobalLS || hLSList == null){
			String discoveryXQuery = DISC_XQUERY;
			discoveryXQuery = discoveryXQuery.replaceAll("<!--addrPath-->", addrPath);
			discoveryXQuery = discoveryXQuery.replaceAll("<!--domain-->", domain);
			discoveryXQuery = discoveryXQuery.replaceAll("<!--type-->", typeAttr);
			Element discReqElem = this.createQueryMetaData(discoveryXQuery);
			hLSMatches = this.discover(this.requestString(discReqElem, null));
		}
		
        String xquery = NODE_XQUERY;
        
        xquery = xquery.replaceAll("<!--addr-->", addr);
        xquery = xquery.replaceAll("<!--type-->", type);
        Element reqElem = this.createQueryMetaData(xquery);
        String request = this.requestString(reqElem, null);
        for(String hLS : hLSMatches){
        	this.log.info("hLS: " + hLS);
        	PSLookupClient lsClient = new PSLookupClient(hLS);
        	Element response = lsClient.query(request);
        	Element datum = lsClient.parseDatum(response, psNS.PS_SERVICE);
        	if(datum != null && datum.getChild("node", this.psNS.TOPO) != null){
        		node = datum.getChild("node", this.psNS.TOPO);
        		break;
        	}
        }
        
        return node;
	}
	/**
	 * Retrieve a service element describing an IDC given a domain it controls
	 * 
	 * @param domain the domain as a URN or DNS name that the IDC controls
	 * @return the &lt;service&gt; as a JDOM Element, null if not found
	 * @throws PSException
	 */
	public Element lookupIDC(String domain) throws PSException{
		Element datum = this.lookupService("IDC", domain, "controls", "");
		if(datum == null){ return null; }		
		Element idc = datum.getChild("service", this.psNS.TOPO);
		return idc;
	}
	
	/**
	 * Retrieves a list of URLs associated with an IDC given the domain
	 * @param domain the domain as a URN or DNS name
	 * @return a list of URLs associated with the IDC, null if none found
	 * @throws PSException
	 */
	public String[] lookupIDCUrl(String domain) throws PSException{
		HashMap<String,Boolean> urls = new HashMap<String,Boolean>();
		Element datum = this.lookupService("IDC", domain, "controls", "/nmtb:port/nmtb:address[@type=\"url\"]");
		if(datum == null){ return null; }	
		List<Element> addrElems = datum.getChildren("address", this.psNS.TOPO);
		if(addrElems == null){ return null; }
		for(Element addrElem : addrElems){
			String key = addrElem.getText();
			if(key == null){ continue; }
			urls.put(key.trim(), true);
		}
		if(urls.size() == 0){ return null; }
		
		return urls.keySet().toArray(new String[urls.size()]);
	}
	
	/**
	 * General method used to find a service such as an IDC or NotificationBroker
	 * 
	 * @param type thetype of service to find
	 * @param domain the domain of the service of interest
	 * @param relation the relation of the service to that domain
	 * @param xpath an xpath expression rooted at service that control what is returned
	 * @return the element found (if any)
	 * @throws PSException
	 */
	public Element lookupService(String type, String id, String relation, String xpath) throws PSException{
		this.log.debug("lookupIDC.id=" + id);
		String[] hLSMatches = this.hLSList;
		Element datum = null;
		if(useGlobalLS || hLSList == null){
			String discoveryXQuery = DISC_XQUERY;
			discoveryXQuery = discoveryXQuery.replaceAll("<!--domain-->", id.replaceAll("urn:ogf:network:domain=", ""));
			discoveryXQuery = discoveryXQuery.replaceAll("<!--addrPath-->", "nmtl3:port/nmtl3:address");
			discoveryXQuery = discoveryXQuery.replaceAll("<!--type-->", "dns");
			Element discReqElem = this.createQueryMetaData(discoveryXQuery);
			hLSMatches = this.discover(this.requestString(discReqElem, null));
		}
		
		String idType = "address";
		if(id.startsWith("urn:ogf:network")){
			idType = "idRef";
		}
		String xquery = IDC_XQUERY;
		xquery = xquery.replaceAll("<!--id-->", id);
		xquery = xquery.replaceAll("<!--type-->", type);
		xquery = xquery.replaceAll("<!--relation-->", relation);
		xquery = xquery.replaceAll("<!--idType-->", idType);
		xquery = xquery.replaceAll("<!--xpath-->", xpath);
        Element reqElem = this.createQueryMetaData(xquery);
        String request = this.requestString(reqElem, null);
        for(String hLS : hLSMatches){
        	this.log.info("hLS: " + hLS);
        	PSLookupClient lsClient = new PSLookupClient(hLS);
        	Element response = lsClient.query(request);
        	datum = lsClient.parseDatum(response, psNS.PS_SERVICE);
        	Element metaData = response.getChild("metadata", psNS.NMWG);
	        if(metaData == null){
	        	throw new PSException("No metadata element in registration response");
	        }
	        Element eventType = metaData.getChild("eventType", psNS.NMWG);
	        if(eventType == null){
	        	continue;
	        }else if(eventType.getText().startsWith("error.ls")){
	        	continue;
	        }else if(!"success.ls.query".equals(eventType.getText())){
	        	continue;
	        }else if(datum != null){ break; }
        }
        
		return datum;
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
		
		int attempts = gLSList.length;
		String errLog = "";
		for(int a = 0; a < attempts; a++){
			try{
				PSLookupClient lsClient = new PSLookupClient(this.gLSList[a]);
		        Element response = lsClient.query(request);
		        Element metaData = response.getChild("metadata", psNS.NMWG);
		        
		        if(metaData == null){
		        	throw new PSException("No metadata element in discovery response");
		        }
		        Element eventType = metaData.getChild("eventType", psNS.NMWG);
		        if(eventType == null){
		        	throw new PSException("No eventType returned");
		        }else if(eventType.getText().startsWith("error.ls")){
		        	Element errDatum = lsClient.parseDatum(response, psNS.NMWG_RESULT);
		        	String errMsg = (errDatum == null ? "An unknown error occurred" : errDatum.getText());
		        	this.log.error(eventType.getText() + ": " + errMsg);
		        	throw new PSException("Global discovery error: " + errMsg);
		        }else if(!"success.ls.query".equals(eventType.getText())){
		        	throw new PSException("Hostname not found because lookup " +
		        						  "returned an unrecognized status");
		        }
		        
		        Element datum = lsClient.parseDatum(response, psNS.PS_SERVICE);
		        if(datum == null){
		        	throw new PSException("No service datum returned from discovery request");
		        }
		        List<Element> accessPointElems = datum.getChildren("accessPoint", psNS.PS_SERVICE);
		        for(int i = 0; i < accessPointElems.size(); i++){
		        	apMap.put(accessPointElems.get(i).getTextTrim(), true);
		        }
		        if(!this.tryAllGlobal){
		        	break;
		        }
			}catch(PSException e){
				errLog += this.gLSList[a] + ": " + e.getMessage() + "\n\n";
			}catch(Exception e){
				errLog += this.gLSList[a] + ": " + e.getMessage() + "\n\n";
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
	 * Registers a "Node" element with the lookup service
	 * 
	 * @param reg a NodeRegistration object with the information to register
	 * @return a HashMap indexed by each home LS contacted and containing the key returned by each
	 * @throws PSException
	 */
	public HashMap<String,String> registerNode(NodeRegistration reg) throws PSException{
		Element metaDataElem = this.createMetaData(this.psNS.DCN);
		if(reg.getKeyElem() != null){
			metaDataElem.addContent(0,reg.getKeyElem());
		}
		Element subjElem = metaDataElem.getChild("subject", this.psNS.DCN);
		subjElem.addContent(reg.getNodeElem());
		return this.register(metaDataElem);
	}
	
	/**
	 * Registers a service such as an IDC or NotificationBroker with the lookup service
	 * 
	 * @param reg a ServiceRegistration object with the details to register
	 * @return a HashMap indexed by each home LS contacted and containing the key returned by each
	 * @throws PSException
	 */
	public HashMap<String,String> registerService(ServiceRegistration reg) throws PSException{
		Element metaDataElem = this.createMetaData(this.psNS.DCN);
		Element subjElem = metaDataElem.getChild("subject", this.psNS.DCN);
		if(reg.getKeyElem() != null){
			metaDataElem.addContent(0, reg.getKeyElem());
		}
		subjElem.addContent(reg.getServiceElem());
		if(reg.getOptionalParamsElem() != null){
			subjElem.addContent(reg.getOptionalParamsElem());
		}
		
		return this.register(metaDataElem);
	}
	
	/**
	 * General registration method that handles creating the top-level metadata and data
	 * and inserts the given metadata to register and an empty data element into the 
	 * top-level structure.
	 * 
	 * @param metaDataElem the metaData to register
	 * @return a HashMap indexed by each home LS contacted and containing the key returned by each
	 * @throws PSException
	 */
	private HashMap<String, String> register(Element metaDataElem) throws PSException{
		HashMap<String,String> keys = new HashMap<String,String>();
		if(hLSList == null){
			throw new PSException("No home lookup services specified!");
		}
		
		for(String hLS : hLSList){
			String request = this.requestString(metaDataElem, null);
			PSLookupClient lsClient = new PSLookupClient(hLS);
			Element response = lsClient.register(request, null);
			Element metaData = response.getChild("metadata", psNS.NMWG);
	        if(metaData == null){
	        	throw new PSException("No metadata element in registration response");
	        }
	        Element eventType = metaData.getChild("eventType", psNS.NMWG);
	        if(eventType == null){
	        	throw new PSException("No eventType returned");
	        }else if(eventType.getText().startsWith("error.ls")){
	        	Element errDatum = lsClient.parseDatum(response, psNS.NMWG_RESULT);
	        	String errMsg = (errDatum == null ? "An unknown error occurred" : errDatum.getText());
	        	this.log.error(eventType.getText() + ": " + errMsg);
	        	throw new PSException("Registration error: " + errMsg);
	        }else if(!"success.ls.register".equals(eventType.getText())){
	        	throw new PSException("Registration returned an unrecognized status");
	        }
	        
	        //Get keys
	        XPath xpath;
			try {
				xpath = XPath.newInstance("nmwg:metadata/nmwg:key/nmwg:parameters/nmwg:parameter[@name='lsKey']");
				xpath.addNamespace(psNS.NMWG);
	            Element keyParam = (Element) xpath.selectSingleNode(response);
	            if(keyParam == null){
	            	throw new PSException("No key in the response");
	            }
	            keys.put(hLS, keyParam.getText());
	            this.log.debug(hLS +"="+keyParam.getText());
			} catch (JDOMException e) {
				this.log.error(e);
				throw new PSException(e);
			}
		}
		
		return keys;
	}
	
	public void deregister(String key) throws PSException{
		if(hLSList == null){
			throw new PSException("No home lookup services specified!");
		}
		
		Element metaDataElem = this.createMetaData(null);
		Element keyElem = new Element("key", this.psNS.NMWG);
		Element paramsElem = new Element("parameters", this.psNS.NMWG);
		Element paramElem = new Element("parameter", this.psNS.NMWG);
		
		keyElem.setAttribute("id", "k"+key.hashCode());
		paramsElem.setAttribute("id", "p"+key.hashCode());
		paramElem.setAttribute("name", "lsKey");
		paramElem.setText(key);
		paramsElem.addContent(paramElem);
		keyElem.addContent(paramsElem);
		metaDataElem.addContent(keyElem);
		for(String hLS : hLSList){
			String request = this.requestString(metaDataElem, null);
			PSLookupClient lsClient = new PSLookupClient(hLS);
			Element response = lsClient.deregister(request, null);
			Element metaData = response.getChild("metadata", psNS.NMWG);
	        if(metaData == null){
	        	throw new PSException("No metadata element in deregistration response");
	        }
	        Element eventType = metaData.getChild("eventType", psNS.NMWG);
	        if(eventType == null){
	        	throw new PSException("No eventType returned");
	        }else if(eventType.getText().startsWith("error.ls")){
	        	Element errDatum = lsClient.parseDatum(response, psNS.NMWG_RESULT);
	        	String errMsg = (errDatum == null ? "An unknown error occurred" : errDatum.getText());
	        	this.log.error(eventType.getText() + ": " + errMsg);
	        	throw new PSException("Deregistration error: " + errMsg);
	        }else if(!"success.ls.deregister".equals(eventType.getText())){
	        	throw new PSException("Registration returned an unrecognized status");
	        }
		}
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
	
	/**
	 * @return true if uses global LS to discover hLS for queries
	 */
	public boolean usesGlobalLS() {
		return useGlobalLS;
	}

	/**
	 * @param useGlobalLS true if uses global LS to discover hLS for queries
	 */
	public void setUseGlobalLS(boolean useGlobalLS) {
		this.useGlobalLS = useGlobalLS;
	}
	
	/**
	 * Generates a new metadata element
	 * 
	 * @param ns the namespace of the subject. if null then no subject
	 * @return the generated metadata
	 */
	private Element createMetaData(Namespace ns){
		Element metaDataElem = new Element("metadata", this.psNS.NMWG);
		metaDataElem.setAttribute("id", "meta" + metaDataElem.hashCode());
		if(ns != null){
			Element subjElem = new Element("subject", ns);
			subjElem.setAttribute("id", "subj"+System.currentTimeMillis());
			metaDataElem.addContent(subjElem);
		}
		return metaDataElem;
	}
	
	/**
	 * Generates a new query metadata element
	 * 
	 * @param query the XQuery to send
	 * @return the generated metadata
	 */
	private Element createQueryMetaData(String query){
		Element metaDataElem = this.createMetaData(this.psNS.XQUERY);
		metaDataElem.getChild("subject", this.psNS.XQUERY).setText(query);
		Element eventType = new Element("eventType", this.psNS.NMWG);
		eventType.setText("http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0");
		metaDataElem.addContent(eventType);
		Element paramsElem = new Element("parameters", this.psNS.XQUERY);
		paramsElem.setAttribute("id", "params"+paramsElem.hashCode());
		Element paramElem = new Element("parameter", this.psNS.NMWG);
		paramElem.setAttribute("name", "lsOutput");
		paramElem.setText("native");
		paramsElem.addContent(paramElem);
		metaDataElem.addContent(paramsElem);
		return metaDataElem;
	}
	
	/**
	 * Converts a metadata element to a String
	 * 
	 * @param elem the metadata element to convert to a string
	 * @param addData if true then add empty data element
	 * @return the metadata and data as a string
	 */
	private String requestString(Element metaData, List<Element> data) {
		XMLOutputter xmlOut = new XMLOutputter();
		StringWriter sw = new StringWriter();
		String result = "";
		
		try {
			xmlOut.output(metaData, sw);
			Element dataElem = new Element("data", this.psNS.NMWG);
			dataElem.setAttribute("metadataIdRef", metaData.getAttributeValue("id"));
			dataElem.setAttribute("id", "data"+dataElem.hashCode());
			if(data != null){
				dataElem.addContent(data);
			}
			xmlOut.output(dataElem, sw);
			result = sw.toString();
		} catch (IOException e) {}
		
		return result;
	}
}