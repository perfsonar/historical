package edu.internet2.perfsonar;

import java.io.IOException;
import java.io.StringWriter;
import java.net.InetAddress;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.UnknownHostException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.List;

import org.apache.commons.httpclient.HttpException;
import org.apache.log4j.Logger;
import org.jdom.Element;
import org.jdom.JDOMException;
import org.jdom.Namespace;
import org.jdom.output.XMLOutputter;
import org.jdom.xpath.XPath;

import edu.internet2.perfsonar.PSBaseClient;
import edu.internet2.perfsonar.PSMessageEventHandler;
import edu.internet2.perfsonar.PSException;
import edu.internet2.perfsonar.PSLookupClient;
import edu.internet2.perfsonar.PSNamespaces;

import edu.internet2.perfsonar.utils.*;

/**
 * Performs lookup operations useful for dynamic circuits netwoking (TS)
 * applications.
 *
 */
public class TSLookupClient implements PSMessageEventHandler {
    private Logger log;
    private String[] gLSList;
    private String[] hLSList;
    private boolean tryAllGlobal;
    private boolean useGlobalLS;
    private PSNamespaces psNS;
    private Element retrievedTopology;
    private HashMap <String, Element> cachedTopologies;
    private HashMap <String, Long> cacheTime;

    static final private long MAXIMUM_CACHE_LENGTH = 300000; // 5 minutes
    static final private String TOPOLOGY_EVENT_TYPE = "http://ggf.org/ns/nmwg/topology/20070809";

    private String GLS_XQUERY = 
        "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
        "declare namespace summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\";\n" +
        "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n" +
        "declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n" +
        "declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
        "for $metadata in /nmwg:store[@type=\"LSStore\"]/nmwg:metadata\n" +
        "    let $metadata_id := $metadata/@id  \n" +
        "    let $data := /nmwg:store[@type=\"LSStore\"]/nmwg:data[@metadataIdRef=$metadata_id]\n" +
        "    where $data/nmwg:metadata/nmwg:eventType[text()=\""+TOPOLOGY_EVENT_TYPE+"\"] and $data/nmwg:metadata/summary:subject/nmtb:domain/nmtb:name[@type=\"dns\" and text()=\"<!--domain_name-->\"]\n" +
        "    return $metadata/perfsonar:subject/psservice:service/psservice:accessPoint\n";

    private String HLS_XQUERY = 
            "   declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n" +
            "   declare namespace summary=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/summarization/2.0/\";\n" +
            "   declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n" +
            "   declare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n" +
            "   declare namespace nmtb=\"http://ogf.org/schema/network/topology/base/20070828/\";\n" +
            "   for $metadata in /nmwg:store[@type=\"LSStore\"]/nmwg:metadata\n" +
            "       let $metadata_id := $metadata/@id  \n" +
            "       let $data := /nmwg:store[@type=\"LSStore\"]/nmwg:data[@metadataIdRef=$metadata_id]\n" +
            "       where $data/nmwg:metadata/nmwg:eventType[text()=\""+TOPOLOGY_EVENT_TYPE+"\"] and $data/nmwg:metadata/*[local-name()=\"subject\"]/*[local-name()=\"domain\" and @id=\"<!--domain_id-->\"]\n" +
            "       return $metadata/perfsonar:subject/psservice:service/psservice:accessPoint\n";

    private String TS_QUERY =
            "<nmwg:message type=\"QueryRequest\" "+
            "   xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"> "+
            "    <nmwg:metadata id=\"meta1\">" +
            "      <nmwg:eventType>"+TOPOLOGY_EVENT_TYPE+"</nmwg:eventType>" +
            "   </nmwg:metadata>" +
            "   <nmwg:data id=\"data1\" metadataIdRef=\"meta1\"/> "+
            "</nmwg:message>";

    /**
     * Creates a new client with the list of Global lookup services to 
     * contact determined by reading the hints file at the provided URL.
     * The result returned by the list file will be randomly re-ordered.
     * 
     * @param hintsFile the URL of the hints file to use to populate the list of global lookup services
     * @throws HttpException
     * @throws IOException
     */
    public TSLookupClient(String hintsFile) throws HttpException, IOException {
        this.log = Logger.getLogger(this.getClass());
        String[] gLSList = PSLookupClient.getGlobalHints(hintsFile, true);
        this.gLSList = gLSList;
        this.hLSList = null;
        this.tryAllGlobal = false;
        this.useGlobalLS = true;
        this.psNS = new PSNamespaces();
        this.cachedTopologies = new HashMap<String, Element>();
        this.cacheTime = new HashMap<String, Long>();
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
    public TSLookupClient(String hintsFile, String[] hLSList) throws HttpException, IOException {
        this.log = Logger.getLogger(this.getClass());
        String[] gLSList = PSLookupClient.getGlobalHints(hintsFile, true);
        this.gLSList = gLSList;
        this.hLSList = hLSList;
        this.tryAllGlobal = false;
        this.useGlobalLS = true;
        this.psNS = new PSNamespaces();
        this.cachedTopologies = new HashMap<String, Element>();
        this.cacheTime = new HashMap<String, Long>();
    }
    
    /**
     * Creates a new client that uses the explicitly set list of global lookup
     * services. 
     * 
     * @param gLSList
     */
    public TSLookupClient(String[] gLSList){
        this.log = Logger.getLogger(this.getClass());
        this.gLSList = gLSList;
        this.hLSList = null;
        this.tryAllGlobal = false;
        this.psNS = new PSNamespaces();
        this.cachedTopologies = new HashMap<String, Element>();
        this.cacheTime = new HashMap<String, Long>();
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
    public TSLookupClient(String[] gLSList, String[] hLSList){
        this.log = Logger.getLogger(this.getClass());
        this.gLSList = gLSList;
        this.hLSList = hLSList;
        this.tryAllGlobal = false;
        this.psNS = new PSNamespaces();
        this.cachedTopologies = new HashMap<String, Element>();
        this.cacheTime = new HashMap<String, Long>();
    }
    
    /**
     * Finds the URN of a host with the given name. 
     * 
     * @param name the name of the host o lookup
     * @return the Topology of the domain given by the specified domain identifier
     * @throws PSException
     */
    public Element getDomain(String domainId) throws PSException{
        Hashtable<String, String> urnInfo = URNParser.parseTopoIdent(domainId);

        if (urnInfo.get("type").equals("empty") == true) {
            return null;
        }

        if (urnInfo.get("type").equals("domain") == false) {
            return null;
        }

        if (this.cacheTime.get(domainId) != null &&  this.cacheTime.get(domainId).longValue() + this.MAXIMUM_CACHE_LENGTH > System.currentTimeMillis()) {
            System.out.println("Found existing");
            Element retTopology = (Element) this.cachedTopologies.get(domainId).clone();

            List<Element> children = this.getElementChildren(retTopology, "domain");
            for (Element child : children) {
                String newDomainId = child.getAttributeValue("id");

                if (newDomainId != null && domainId.equals(newDomainId) == false) {
                    retTopology.removeContent(child);
                }
            }

            return retTopology;
        }


        String domainName = urnInfo.get("domainValue");

        String urn = null;
        String[] hLSMatches = this.hLSList;
        if(useGlobalLS || hLSList == null){
            try {
                String discoveryXQuery = GLS_XQUERY;
                discoveryXQuery = discoveryXQuery.replaceAll("<!--domain_name-->", domainName);
                Element discReqElem = this.createQueryMetaData(discoveryXQuery);
                hLSMatches = this.findServices(this.gLSList, this.tryAllGlobal, this.requestString(discReqElem, null));
            } catch (PSException e) {
                // no hLS elements returned
                return null;
            }
        }

        String [] TSMatches;

        try {
            String xquery = HLS_XQUERY;
            xquery = xquery.replaceAll("<!--domain_id-->", domainId);
            Element reqElem = this.createQueryMetaData(xquery);
            TSMatches = this.findServices(hLSMatches, true, this.requestString(reqElem, null));
        } catch (PSException e) {
            return null;
        }

        for(String ts_url : TSMatches) {
            PSBaseClient pSClient = new PSBaseClient(ts_url);

            pSClient.sendMessage_CB(TS_QUERY, this, null);
            if (this.retrievedTopology != null) {
                Element origTopology = (Element) this.retrievedTopology.clone();

                List<Element> children = this.getElementChildren(this.retrievedTopology, "domain");
                for (Element child : children) {
                    // construct the domain topology identifier
                    String newDomainId = child.getAttributeValue("id");

                    this.cachedTopologies.put(newDomainId, origTopology);
                    this.cacheTime.put(newDomainId, new Long(System.currentTimeMillis()));

                    if (domainId.equals(newDomainId) == false) {
                        this.retrievedTopology.removeContent(child);
                    }
                }

                return this.retrievedTopology;
            }
        }

        return null;
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
    public String[] findServices(String [] lookupServices, boolean tryAll, String request) throws PSException{
        String[] accessPoints = null;
        HashMap<String, Boolean> apMap = new HashMap<String, Boolean>();
       
        String errLog = "";
        for (String ls : lookupServices) { 
            try{
                PSLookupClient lsClient = new PSLookupClient(ls);
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
                if(!tryAll){
                    break;
                }
            }catch(PSException e){
                errLog += ls + ": " + e.getMessage() + "\n\n";
            }catch(Exception e){
                errLog += ls + ": " + e.getMessage() + "\n\n";
            }
        }
        
        if(apMap.isEmpty()){
            throw new PSException("No services found after trying lookup services:\n" + errLog);
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
            subjElem.setAttribute("id", "subj"+subjElem.hashCode());
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

    public void handleMetadataDataPair(Element metadata, Element data, HashMap <String, Element> metadataMap, String messageType, Object arg) {
        if (messageType.equals("QueryResponse")) {
            Element eventType_elm = metadata.getChild("eventType", this.psNS.NMWG);
            if (eventType_elm == null) {
                this.log.info("The metadata/data pair doesn't have an event type");
                return;
            }

            if (!eventType_elm.getValue().equals("http://ggf.org/ns/nmwg/topology/20070809")) {
                this.log.info("The metadata/data pair has an unknown event type: "+eventType_elm.getValue());
                return;
            }

            Element topo = data.getChild("topology", this.psNS.TOPO);

            if (topo == null) {
                this.log.info("No topology located in data");
                return;
            }

            this.retrievedTopology = topo;
        } else {
            this.log.error("Received a metadata/data pair from an unknown message type: "+messageType);
        }
    }

    private List<Element> getElementChildren(Element e, String name) {
        ArrayList<Element> filteredChildren = new ArrayList<Element>();

        List<Element> children = e.getChildren();

        for (Element child : children) {
            if (child.getName().equals(name)) {
                filteredChildren.add(child);
            }
        }

        return filteredChildren;
    }
}
