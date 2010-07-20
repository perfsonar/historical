package net.perfsonar.topology.client;

import java.io.FileOutputStream;
import java.io.IOException;

import edu.internet2.perfsonar.PSException;
import edu.internet2.perfsonar.TSLookupClient;
import org.apache.commons.httpclient.HttpException;
import org.jdom.Element;
import org.jdom.output.Format;
import org.jdom.output.XMLOutputter;

public class PSTopoPuller {
    public static void saveTopology(Element domain, String filename) throws HttpException, IOException, PSException {
        XMLOutputter op = new XMLOutputter(Format.getPrettyFormat());
        FileOutputStream os = new FileOutputStream(filename);
        op.output(domain, os);
    }
    public static void printTopology(Element domain) throws HttpException, IOException, PSException {
        XMLOutputter op = new XMLOutputter(Format.getPrettyFormat());
        op.output(domain, System.out);

    }
    public static Element pullTopology(String url, String id) throws HttpException, IOException, PSException {
        String[] tsList = new String[1];
        tsList[0] = url;
        TSLookupClient psClient = new TSLookupClient();
        psClient.setTSList(tsList);
        Element domain = psClient.getDomain(id); //, "http://ogf.org/schema/network/topology/base/20070828/");
        if (domain == null) {
            throw new IOException("No domain data from topology server");
        }
        return domain;
    }
}
