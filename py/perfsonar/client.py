from perfsonar.message import psMessageBuilder, psMessageReader
from lxml import etree
import logging
from httplib import HTTPConnection
log = logging.getLogger(__name__)

"""
Module containing client-side utilities.
"""

class SimpleClient(object):
    # This is minimal xml message to feed to the psMessageReader
    # class for successful instantiation for the type() test.
    testString = '<foo:message xmlns:foo="foo" type="bar"></foo:message>'
    
    def __init__(self, host, port, uri):
        self.host = host
        self.port = port
        self.uri  = uri
        self.message = None
        
    def setMessage(self,message):
        """
        Adds the next message payload to send.  Will accept a xml string
        or one of the psMessage objects.  NOTE: if a string is passed in
        it will be tested and sanitized by the psMessageReader class. If
        the message is not valid and exception will be raised.
        """
        if type(message) == str:
            # use the message reader class to sanitize it
            log.debug('Passed a string - converting to reader object')
            message = psMessageReader(message)
            
        if type(message) == type(psMessageBuilder('foo','bar')):
            log.debug('Initializing from msg builder object')
        elif type(message) == type(psMessageReader(self.testString)):
            log.debug('Initializing from msg reader object')
        else:
            er = 'Bad initialization with type: %s' % type(message)
            log.error(er)
            raise RuntimeError(er)
            
        self.message = message.message
        
    def soapifyMessage(self):
        """
        Adds soap headers to the passed in message before sending.
        """
        headerString = """<SOAP-ENV:Envelope 
 xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
 xmlns:xsd="http://www.w3.org/2001/XMLSchema"
 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
 xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
<SOAP-ENV:Header/>
<SOAP-ENV:Body>
</SOAP-ENV:Body>
</SOAP-ENV:Envelope>
        """
        soap = etree.fromstring(headerString)
        for i in soap.iterchildren():
            if i.tag.split('}')[1] == 'Body':
                i.append(self.message)

        return etree.tostring(soap)
        
    def sendAndGetResponse(self):
        """
        Sends the currently set message and hands back the response
        as a psMessageReader object.
        """
        conn = HTTPConnection(self.host, self.port)
        conn.connect()
        headers = {'SOAPAction':'', 'Content-Type': 'text/xml'}
        conn.request('POST', self.uri, self.soapifyMessage(), headers)
        resp = conn.getresponse()
        response = resp.read()
        conn.close()
        
        return psMessageReader(response)
        
if __name__ == '__main__':
    pass