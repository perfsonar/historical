"""nmwg namespaces

"""
nsdict = {
    'nmwg':"http://ggf.org/ns/nmwg/base/2.0/",
    'nmtm':"http://ggf.org/ns/nmwg/time/2.0/",
    'nmwgt':"http://ggf.org/ns/nmwg/topology/2.0/",
    'nmwgt3':"http://ggf.org/ns/nmwg/topology/base/3.0/",
    'snmp':"http://ggf.org/ns/nmwg/tools/snmp/2.0/",
    'select':"http://ggf.org/ns/nmwg/ops/select/2.0/",
    'neterr':"http://ggf.org/ns/nmwg/characteristic/errors/2.0/",
    'netdisc':"http://ggf.org/ns/nmwg/characteristic/discards/2.0/",
    'netutil':"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/"
}

# The namespaces that the individual elements exist in.
elementNS = {
    # "primary" element types
    'message': 'nmwg',
    'data': 'nmwg',
    'datum': 'nmwg',
    'metadata': 'nmwg',
    'parameter': 'nmwg',
    'parameters': 'nmwg',
    'subject': 'netutil', # this is a sane default
    'eventType': 'nmwg',
    'key': 'nmwg',
    # types for an interface block
    'interface': 'nmwgt',
    'hostName': 'nmwgt',
    'ifAddress': 'nmwgt',
    'ifName': 'nmwgt',
    'ifIndex': 'nmwgt',
    'ifDescription': 'nmwgt',
    'direction': 'nmwgt',
    'authRealm': 'nmwgt',
    'capacity': 'nmwgt',
    'description': 'nmwgt',
    'urn': 'nmwgt3'
}

def elementNameToNS(ename):
    return nsdict[elementNS[ename]]
    
def nsToPrefix(ns):
    for k,v in nsdict.items():
        if v == ns:
            return k
    return None
