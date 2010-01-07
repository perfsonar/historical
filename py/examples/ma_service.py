from perfsonar.server import psService, serveWithCherryPy
from lxml import etree

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
        log.debug('Fetching...')
        # do something
        return ""
        
    def measurementStoreRequest(self,message):
        log.debug('Storing...')
        # do something
        message = makeResponse()
        return ""
        
if __name__ == '__main__':
    # Change the logging level to DEBUG to see the messages
    # and such.
    logging.basicConfig(level=logging.DEBUG)
    service = MeasurementArchiveService()
    log.debug("starting server")
    # Ctrl-C will kill the server.
    serveWithCherryPy('localhost', 8080, service)
