from perfsonar.message import psMessageReader
import logging
from lxml import etree, objectify

message="""
<SOAP-ENV:Envelope xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Header/>
  <SOAP-ENV:Body>
<nmwg:message type="MetadataKeyRequest" id="metadataKeyRequest1"
              xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/"
              xmlns:neterr="http://ggf.org/ns/nmwg/characteristic/errors/2.0/"
              xmlns:netdisc="http://ggf.org/ns/nmwg/characteristic/discards/2.0/"
              xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/"
              xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/"
              xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/"
              xmlns:snmp="http://ggf.org/ns/nmwg/tools/snmp/2.0/"
              xmlns:nmtm="http://ggf.org/ns/nmwg/time/2.0/">

  <nmwg:metadata id="meta1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="s-in-netutil-1">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/" />
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>
  </nmwg:metadata>

  <nmwg:data id="data1" metadataIdRef="meta1" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/"/>

</nmwg:message>


  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""

message1="""
<SOAP-ENV:Envelope xmlns:ns0="http://perfsonar.org/services/measurementArchive" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/">
  <SOAP-ENV:Header/>
  <SOAP-ENV:Body>
    <nmwg:message xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" type="MeasurementArchiveStoreRequest" id="msg4">
      <nmwg:parameters id="msgparam1">
        <nmwg:parameter name="authToken">Internet2</nmwg:parameter>
        <nmwg:parameter name="timeValue">1138699951</nmwg:parameter>
        <nmwg:parameter name="timeType">unix</nmwg:parameter>
      </nmwg:parameters>
      <nmwg:metadata id="meta1">
        <netutil:subject id="subj1">
          <nmwgt:interface>
            <nmwgt:hostname>test-hostName</nmwgt:hostname>
            <nmwgt:ifAddress type="ipv4">10.1.2.2</nmwgt:ifAddress>
            <nmwgt:ifName>test-0</nmwgt:ifName>
            <nmwgt:ifDescription>test desc</nmwgt:ifDescription>
            <nmwgt:direction>in</nmwgt:direction>
            <nmwgt:authRealm>TestRealm</nmwgt:authRealm>
            <nmwgt:capacity>1000BaseT</nmwgt:capacity>
          </nmwgt:interface>
        </netutil:subject>
        <nmwg:parameters>
          <nmwg:parameter name="dataSourceStep">300</nmwg:parameter>
          <nmwg:parameter name="dataSourceType">COUNTER</nmwg:parameter>
          <nmwg:parameter name="dataSourceHeartbeat">1800</nmwg:parameter>
          <nmwg:parameter name="dataSourceMinValue">0</nmwg:parameter>
          <nmwg:parameter name="dataSourceMaxValue">10000000000000</nmwg:parameter>
        </nmwg:parameters>
        <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>
      </nmwg:metadata>
      <nmwg:data metadataIdRef="meta1" id="data1">
        <nmwg:datum valueUnits="bps" timeValue="1179149601" value="12345" timeType="unix"/>
      </nmwg:data>
    </nmwg:message>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""

message3 = """
  <nmwg:message id="msg5"
                type="MeasurementArchiveStoreRequest"
                xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" 
                xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">

    <!-- Optional message level parameters -->
    <nmwg:parameters id="msgparam1">
      <nmwg:parameter name="authToken">Internet2</nmwg:parameter>	
      <nmwg:parameter name="timeValue">1138699961</nmwg:parameter>	
      <nmwg:parameter name="timeType">unix</nmwg:parameter>	
    </nmwg:parameters>  

    <nmwg:metadata id="meta1">
      <nmwg:key id="keyid">
        <nmwg:parameters id="param1">
          <nmwg:parameter name="file">/root/Download/dev/sonar-head-20060224/sonar/perfsonar/atla-hstn.rrd</nmwg:parameter>
          <nmwg:parameter name="dataSource">output</nmwg:parameter>
        </nmwg:parameters>
      </nmwg:key>
    </nmwg:metadata>

    <nmwg:data id="data1" metadataIdRef="meta1">
      <nmwg:datum value="12345" timeValue="1138617912" timeType="unix"/>
    </nmwg:data>

  </nmwg:message>
"""

message4 = """
<nmwg:message xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/" xmlns:select="http://ggf.org/ns/nmwg/ops/select/2.0/" type="SetupDataRequest" id="#message1">
  <nmwg:metadata id="#in">
    <netutil:subject id="#netutil1">
      <nmwgt:interface>
        <nmwgt:ifName>xe-0/0/0</nmwgt:ifName>
        <nmwgt:hostName>albu-sdn1</nmwgt:hostName>
        <nmwgt:direction>in</nmwgt:direction>
        <nmwgt:authRealm>ESnet-Public</nmwgt:authRealm>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:metadata id="#out">
    <netutil:subject id="#netutil1">
      <nmwgt:interface>
        <nmwgt:ifName>xe-0/0/0</nmwgt:ifName>
        <nmwgt:hostName>albu-sdn1</nmwgt:hostName>
        <nmwgt:direction>out</nmwgt:direction>
        <nmwgt:authRealm>ESnet-Public</nmwgt:authRealm>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:metadata id="#metaIn">
    <select:subject id="#periodIn" metadataIdRef="#in"/>
    <nmwg:parameters id="#paramsIn">
      <nmwg:parameter name="endTime">1254164160</nmwg:parameter>
      <nmwg:parameter name="resolution">30</nmwg:parameter>
      <nmwg:parameter name="consolidationFunction">AVERAGE</nmwg:parameter>
      <nmwg:parameter name="startTime">1254120960</nmwg:parameter>
    </nmwg:parameters>
    <nmwg:eventType>http://ggf.org/ns/nmwg/ops/select/2.0</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:metadata id="#metaOut">
    <select:subject id="#periodOut" metadataIdRef="#out"/>
    <nmwg:parameters id="#paramsOut">
      <nmwg:parameter name="endTime">1254164160</nmwg:parameter>
      <nmwg:parameter name="resolution">30</nmwg:parameter>
      <nmwg:parameter name="consolidationFunction">AVERAGE</nmwg:parameter>
      <nmwg:parameter name="startTime">1254120960</nmwg:parameter>
    </nmwg:parameters>
    <nmwg:eventType>http://ggf.org/ns/nmwg/ops/select/2.0</nmwg:eventType>
  </nmwg:metadata>
  <nmwg:data metadataIdRef="#metaIn" id="#dataIn"/>
  <nmwg:data metadataIdRef="#metaOut" id="#dataOut"/>
</nmwg:message>
"""

message5 = """
<SOAP-ENV:Envelope xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <SOAP-ENV:Header/>
    <SOAP-ENV:Body>
        <nmwg:message xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" messageIdRef="metadataKeyRequest1" id="message.2060302" type="MetadataKeyResponse">
            <nmwg:metadata metadataIdRef="m1" id="metadata.13505125">
                <nmwg:key id="k1">
                    <nmwg:parameters id="pk1">
                        <nmwg:parameter name="maKey">65590b34956cf3bb4b500f974baa90f5</nmwg:parameter>
                        <nmwg:parameter name="startTime">1254725704</nmwg:parameter>
                        <nmwg:parameter name="endTime">1254768304</nmwg:parameter>
                        <nmwg:parameter name="consolidationFunction">AVERAGE</nmwg:parameter>
                        <nmwg:parameter name="resolution">60</nmwg:parameter>
                    </nmwg:parameters>
                </nmwg:key>
            </nmwg:metadata>
            <nmwg:data metadataIdRef="metadata.13505125" id="data.3274756">
                <nmwg:key xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="k1">
                    <nmwg:parameters id="pk1">
                        <nmwg:parameter name="maKey">65590b34956cf3bb4b500f974baa90f5</nmwg:parameter>
                        <nmwg:parameter name="startTime">1254725704</nmwg:parameter>
                        <nmwg:parameter name="endTime">1254768304</nmwg:parameter>
                        <nmwg:parameter name="consolidationFunction">AVERAGE</nmwg:parameter>
                        <nmwg:parameter name="resolution">60</nmwg:parameter>
                    </nmwg:parameters>
                </nmwg:key>
            </nmwg:data>
        </nmwg:message>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""

# this is the response from a metadata dump
message6 = """
<nmwg:message xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" messageIdRef="metadataKeyRequest1" id="message.4730549" type="MetadataKeyResponse">
  <nmwg:metadata xmlns:nmwg="http://ggf.org/ns/nmwg/base/2.0/" id="metadata.10295355" metadataIdRef="rtr.atla.net.internet2.edu--xe-2/0/0.0-in">
    <netutil:subject xmlns:netutil="http://ggf.org/ns/nmwg/characteristic/utilization/2.0/" id="64.57.28.243">
      <nmwgt:interface xmlns:nmwgt="http://ggf.org/ns/nmwg/topology/2.0/">
        <nmwgt:ifAddress type="ipv4">64.57.28.58</nmwgt:ifAddress>
        <nmwgt:hostName>rtr.atla.net.internet2.edu</nmwgt:hostName>
        <nmwgt:ifName>xe-2/0/0.0</nmwgt:ifName>
        <nmwgt:direction>in</nmwgt:direction>
        <nmwgt:capacity>10000000000</nmwgt:capacity>
        <nmwgt:description>BACKBONE: ATLA-WASH 10GE | I2-ATLA-WASH-10GE-05133</nmwgt:description>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>
    <nmwg:parameters id="1">
      <nmwg:parameter name="supportedEventType">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>
      <nmwg:parameter name="supportedEventType">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>
    </nmwg:parameters>
  </nmwg:metadata>
  <nmwg:data metadataIdRef="metadata.10295355" id="data.9511015">
    <nmwg:key>
      <nmwg:parameters id="params.0">
        <nmwg:parameter name="maKey">a593c5016d0778e59d76c6ba42fffc3a</nmwg:parameter>
      </nmwg:parameters>
    </nmwg:key>
  </nmwg:data>
</nmwg:message>  
"""

def main():
    logging.basicConfig(level=logging.DEBUG,
                        format="%(levelname)s: %(name)s: %(funcName)s : %(message)s")
                        
    # Can be initialized by either an XML string or an etree.Element
    # object as is used in the server dispatch library.
    reader= psMessageReader(message6)
    
    # Accessors for message Id and Type information
    print 'id:', reader.getMessageId()
    print 'id ref:', reader.getMessageIdRef()
    print 'msg type:', reader.getMessageType()
    
    # Access lists of data, metadata and param block ids
    print 'data blocks:', reader.getDataBlockIds()
    print 'metadata:', reader.getMetadataBlockIds()
    print 'message params:', reader.getParamBlockIds()
    
    # Fetch a message-level block of parameters and their values
    # as a python dict
    for i in reader.getParamBlockIds():
        print '========='
        print i, ':', reader.fetchMessageParams(i)
        # or
        p = reader.getParameters(i)
        print p.params
        print p.id
        
    # Retrieve information from a metadata block
    
    for i in reader.getMetadataBlockIds():
        print '========='
        print i, 'attributes :', reader.fetchMetadataAttributes(i)
        print i, 'subject :', reader.fetchMetadataSubject(i)
        print i, 'interface :', reader.fetchMetadataInterface(i)
        print i, 'params :', reader.fetchMetadataParams(i)
        print i, 'event type :', reader.fetchMetadataEventType(i)
        print i, 'key :', reader.fetchMetadataKey(i)
        # or like this:
        m = reader.getMetadata(i)
        print m.id, ':'
        print m.attribs
        print m.subject
        print m.interface
        print m.params
        print m.eventType
        print m.key
        
    for i in reader.getDataBlockIds():
        print '========='
        print i, 'attributes :', reader.fetchDataAttributes(i)
        print i, 'datum values :', reader.fetchDataDatumValues(i)
        print i, 'key: ', reader.fetchDataKey(i)
        # or like this:
        d = reader.getData(i)
        print d.id, ':'
        print d.attribs
        print d.datumValues
        print d.key
    pass
    
if __name__ == '__main__':
    main()