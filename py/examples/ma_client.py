from httplib import HTTPConnection

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

message2="""
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

message3 = """
<SOAP-ENV:Envelope xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
                   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Header/>
  <SOAP-ENV:Body>
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
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"""

def main():
    messages = (message1, message2, message3)
    conn = HTTPConnection('localhost', 8080)
    conn.connect()
    headers = {'SOAPAction':'', 'Content-Type': 'text/xml'}
    for message in messages:
        conn.request('POST', '/', message, headers)
        resp = conn.getresponse()
        response = resp.read()
        print response
    conn.close()
    
if __name__ == '__main__':
    main()
