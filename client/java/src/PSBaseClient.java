package net.es.oscars.perfsonar;

import net.es.oscars.perfsonar.*;
import java.util.*;
import java.io.*;

import org.apache.log4j.*;

import org.jdom.*;
import org.jdom.input.SAXBuilder;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;

import org.apache.commons.httpclient.HttpClient;
import org.apache.commons.httpclient.HttpException;
import org.apache.commons.httpclient.methods.PostMethod;
import org.apache.commons.httpclient.methods.StringRequestEntity;

import org.xml.sax.SAXException;
import java.lang.Exception;
import org.jdom.xpath.XPath;

public class PSBaseClient {
    String url;
    Namespace nmwgNs;

    private Logger log;

    public PSBaseClient(String url) {
        this.url = url;
        this.log = Logger.getLogger(this.getClass());
        this.nmwgNs = Namespace.getNamespace("nmwg", "http://ggf.org/ns/nmwg/base/2.0/");
    }

    private String addSoapEnvelope(String request) {
        String ret_request =
            "<?xml version='1.0' encoding='UTF-8'?>" +
            "<SOAP-ENV:Envelope xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\" " +
            "     xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" " +
            "     xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" " +
            "     xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\"> " +
            "    <SOAP-ENV:Header/> "+
            "    <SOAP-ENV:Body> "+
            request +
            "</SOAP-ENV:Body>" +
            "</SOAP-ENV:Envelope>";

        return ret_request;
    }

    public void sendMessage_CB(String request, PSMessageEventHandler ev, Object arg) {
        Element message = null;

        message = this.sendMessage(request);
        if (message != null)
            this.parseMessage(message, ev, arg);
    }

    public Element sendMessage(String request) {
        Element message = null;

	this.log.info("Sending request: "+request);

        if (request.indexOf("SOAP-ENV") == -1) {
            request = this.addSoapEnvelope(request);
        }

        //Generate and send response
        try {
             SAXBuilder xmlParser = new SAXBuilder();

            this.log.info("Connecting to "+this.url);
            PostMethod postMethod = new PostMethod(this.url);
            StringRequestEntity entity = new StringRequestEntity(request, "text/xml",null);
            postMethod.setRequestEntity(entity);

            HttpClient client = new HttpClient();

            this.log.info("Sending post");
            int statusCode = client.executeMethod(postMethod);
            this.log.info("Post done");

            String response = postMethod.getResponseBodyAsString();
            ByteArrayInputStream in = new ByteArrayInputStream(response.getBytes());
	    this.log.info("Received response: "+response);
            this.log.info("Parsing start");
            Document responseMessage = xmlParser.build(in);
            this.log.info("Parsing done");

            this.log.info("Looking for message");
            XPath xpath = XPath.newInstance("//nmwg:message");
            xpath.addNamespace(this.nmwgNs.getPrefix(), this.nmwgNs.getURI());

            message = (Element) xpath.selectSingleNode(responseMessage.getRootElement());
        } catch (Exception e) {
            this.log.error("Error: " + e.getMessage());
        }

        if (message == null) {
            this.log.info("No message in response");
        }

        return message;
    }

    public void parseMessage(Element message, PSMessageEventHandler ev, Object arg) {
        this.log.info("Looking for metadata");

        String messageType = message.getAttributeValue("type");
        if (messageType == null) {
            messageType = "";
        }

        HashMap <String, Element> metadataMap = new HashMap<String, Element>();

        List<Element> metadata_elms = message.getChildren("metadata", nmwgNs);
        for (Element metadata : metadata_elms) {
            String md_id = metadata.getAttributeValue("id");
            if (md_id == null)
                continue;

            metadataMap.put(md_id, metadata);
        }

        for (Element metadata : metadata_elms) {
            String md_id = metadata.getAttributeValue("id");
            if (md_id == null)
                continue;

            List<Element> data_elms = message.getChildren("data", nmwgNs);
            for (Element data : data_elms) {
                String md_idRef = data.getAttributeValue("metadataIdRef");

                if (md_idRef.equals(md_id) == false) {
                    this.log.info("metadata: "+md_id+" data_mdIdref: "+md_idRef);
                    continue;
                }

                ev.handleMetadataDataPair(metadata, data, metadataMap, messageType, arg);
            }
        }
    }
}
