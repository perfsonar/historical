from perfsonar.server import psService, serveWithCherryPy
from perfsonar.message import psMessageBuilder, psMessageReader

from time import time
import logging
log = logging.getLogger(__name__)


# This class name is the name of the service that will be exposed.
class MeasurementArchiveService(psService):
    # Set the target namespace of your service - do not use
    # http://ggf.org/ns/nmwg/base/2.0/ or the namespace prefixes
    # in the returned message will get a little messed up.
    __tns__ = 'http://perfsonar.org/services/measurementArchive'
    
    # The dispatch map takes care of mapping the "type" attribute
    # in the nmwg:message element to the proper method to be called.
    # The dict key is the value of the type attribute and the value
    # is the name of the method you want called.  The superclass will
    # take care of calling the right method - exceptions will be 
    # raised and logged if the map is incomplete.
    dispatchmap = {
    'MetadataKeyRequest': 'metadataKeyRequest',
    'MeasurementArchiveStoreRequest': 'measurementStoreRequest'
    }
    
    # The handler methods have an lxml.etree object containing the
    # nmwg:message element passed in as the argument "message".  It 
    # is expecting an lxml.etree object containing the return message
    # to be returned (these are currently just returning the input
    # message) with the nmwg:message as the top-level element.
    
    # NOTE: any references to an "ElementTree" object are in fact
    # lxml.etree objects.  Soaplib does an "import as" maneuver 
    # presumably since they used to use the ElementTree lib.
    def metadataKeyRequest(self, message):
        log.debug('Fetching metadata...')
        messageIn = psMessageReader(message)
        # Read data from the request.
        requestId = messageIn.getMessageId()
        dataBlockId = messageIn.getDataBlockIds()[0]
        data = messageIn.getData(dataBlockId)
        metadataRef = data.attribs['metadataIdRef']
        md = messageIn.getMetadata(metadataRef)
        subjectNS = md.subject['ns']
        subjectId = md.subject['id']
        eventType = md.eventType
        # Log for debug
        log.debug('*** request id: %s' % requestId)
        log.debug('*** data id: %s' % dataBlockId)
        log.debug('*** metadata ref/id: %s' % metadataRef)
        log.debug('*** subject ns: %s' % subjectNS)
        log.debug('*** subject id: %s' % subjectId)
        log.debug('*** event type: %s' % eventType)
        
        # Create the response message component.
        messageOut = psMessageBuilder('message.%s' % time(), 'MetadataKeyResponse',
                                        messageIdRef=requestId)
                                        
        # Do some looping retrieval computations and add the appropriate 
        # sections to the response.  Using faked up data here from some
        # other SNMP MA for an example.
        for i in range(0, 1):
            metadataId = 'metadata.%s' % time()
            interfaceData = {
            'ifAddress type="ipv4"':'64.57.28.58',
            'hostName':'rtr.atla.net.internet2.edu',
            'ifName':'xe-2/0/0.0',
            'direction':'in',
            'capacity':'10000000000',
            'description':'BACKBONE: ATLA-WASH 10GE | I2-ATLA-WASH-10GE-05133'
            }
            metaParams = {'supportedEventType':['http://ggf.org/ns/nmwg/tools/snmp/2.0',
            'http://ggf.org/ns/nmwg/characteristic/utilization/2.0']}
            messageOut.addMetadataBlock(metadataId,
                        metadataIdRef='rtr.atla.net.internet2.edu--xe-2/0/0.0-in',
                        subject='64.57.28.243',
                        subjectType='interface',
                        subjectData=interfaceData,
                        eventType='http://ggf.org/ns/nmwg/characteristic/utilization/2.0',
                        params=metaParams,
                        paramid='1')
            dataBlockId = 'data.%s' % time()
            messageOut.addDataBlock(dataBlockId, metadataIdRef=metadataId)
            
            keyParams = {'maKey': 'a593c5016d0778e59d76c6ba42fffc3a'}
            messageOut.addKeyToDataBlock(dataBlockId, paramid='params.0',params=keyParams)
                                        
        return messageOut.message
        
    def measurementStoreRequest(self,message):
        log.debug('Storing...')
        # do something
        return message
        
if __name__ == '__main__':
    # Change the logging level to DEBUG to see the messages
    # and such.
    logging.basicConfig(level=logging.DEBUG,
                        format="%(levelname)s: %(name)s: %(funcName)s : %(message)s")
    service = MeasurementArchiveService()
    log.debug("starting server")
    # Ctrl-C will kill the server.
    serveWithCherryPy('localhost', 8080, service)
