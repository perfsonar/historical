#!/usr/bin/env python
#
# test_PS.py
# Brian Tierney:  bltierney@es.net
#
# This script is used to  run and time a set of sample querys using the perfSONAR
# generic client client.pl
#
# Input: a config file with the following format
#  <perfSONAR-tests>
#    <requestDir>/path/toXML/files</requestDir>
#    <getAll>MetadataKeyRequest_getAll.xml</getAll>
#    <test>
#       <input>testfile.xml</input>
#       <description>Test description.</description>
#       <expected_output>XML tags/attributes to look for in result</expected_output>
#    </test>
#  </perfSONAR-tests>
#
# output: Pass/Fail messages and performance information
#
# To Do:
#   do each test 2 times, one with bad input, to test for error message
#   general cleanup
#   better error handling / error messages
#   using too many temporary files! (but helpful for debugging) Store results in memory?
#
# Possible improvements:
#    ability to specify namespace in the test config file?
#    add ability to specify element text and attrib values in test config file?
#    verify that data returned looks right (ie: start/end times, step size, etc.)
#    do schema validation of reply?
#    use python 'csv' module for handling csv file?
#
import time, sys, os, string, os.path, random
from stat import *
#from subprocess import *
from optparse import OptionParser
#from xml.etree import ElementTree
from elementtree import ElementTree

PSHOME = os.getenv("PSHOME")
if PSHOME == None:
    print "Error: PSHOME env variable not set"
    sys.exit(-1)

timingResultsFile = "results.csv"

# location of client.pl
client_script = PSHOME+"/client/client.pl "

# log files for this program go here
logdir = "/tmp/"

defaultService = "http://localhost:8081/"
requestDir = "/test_harness/requests/"
configFile = "snpmMA-test-config.xml"

# define namespaces
NMWG = "{http://ggf.org/ns/nmwg/base/2.0/}"
# XXX: delete this when bug is fixed
NMWG2 = "{http://ggf.org/ns/nmwg/base/2.0}"   # BUG? sometimes there is no trailing '/'
NMWGT = "{http://ggf.org/ns/nmwg/topology/2.0/}"
NMWGS = "{http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/}"
NMWGC = "{http://ggf.org/ns/nmwg/characteristic/utilization/2.0/}"
TOPO  = "{http://ogf.org/schema/network/topology/base/20070828/}"
IPERF = "{http://ggf.org/ns/nmwg/tools/iperf/2.0/}"
NMWGR = "{http://ggf.org/ns/nmwg/result/2.0/}"  # for error/status messages only

#NMWG_ALL = [NMWG, NMWG2, NMWGT, NMWGR, NMWGS, IPERF]
NMWG_ALL = [NMWG, NMWGT, NMWGS, NMWGC, IPERF, TOPO, NMWGR]

verbose = 0

#######################################################

def getOptions():
    """ add Comment here
    """
    global verbose, PSHOME
    parser = OptionParser()
    parser.add_option("-u", "--url", action="store", type="string", dest="PS_url",
                  default=defaultService,
                  help="Connect to MA and LS service at this URL [default = %default]", metavar="URL")
    parser.add_option("-D", "--dir", action="store", type="string", dest="requestDir",
                  default=requestDir,
                  help="Directory where XML request files are found [default = %default]", metavar="PATH")
    parser.add_option("-c", "--cfg", action="store", type="string", dest="configFile",
                  default=configFile,
                  help="Text configuration file [default = %default]", metavar="CFG")
    parser.add_option("-t", "--csv",
                  action="store_true", dest="csv", default=False,
                  help="write timing results in CSV format to file [default = %default]" )
    parser.add_option("-d", "--debug",
                  action="store_true", dest="debug", default=False,
                  help="print lots of status messages to stdout [default = %default]")
    parser.add_option("-v", "--verbose",
                  action="store_true", dest="verbose", default=False,
                  help="print additional status messages to stdout [default = %default]")
    (options, args) = parser.parse_args()

    if options.verbose:
        verbose = 1
        print "\nUsing the following Settings: "
        print "   url: ", options.PS_url
        print "   configFile: ", options.configFile
        print "   Requests: ", options.requestDir
        print "   verbose: ", options.verbose
        print "\n"

    return(options)

#######################################################

def loadTestConfigFile(filename):
    """ add Comment here
    """
    global requestDir, options

    inputFile = []
    testDescription = []
    expectedOutput = []  # array of dictionaries of tags / attributes to look for
    getAllRequest = ""

    try:
        tree = ElementTree.parse(filename)
    except:
	print "Error opening test config file: ", filename
        sys.exit(-1)

    e = tree.find("//getAll")
    try:
        getAllRequest = e.text
    except:
        getAllRequest = ""
        #print "getAll not found in config file, Using default value for getAllRequest"

    e = tree.find("//requestDir")
    try:
        requestDir = PSHOME + "/" + e.text
    except:
        print "requestDir not found in config file, Using default value for requestDir"
        requestDir = PSHOME + requestDir

    testNum = 0
    for e in tree.findall("//test"):
        found_tag = 0
        t = []
        expectedOutput.append(t)
        for n in e:
            if n.tag == "input":
                inputFile.append(n.text)
                found_tag += 1
            if n.tag == "description":
                testDescription.append(n.text)
                found_tag += 1
            if n.tag == "expected_output":
                #print "found EO: text %s, attr: " % n.text, n.attrib
                try:
                    a = n.attrib['attrib']
                except:
                    a = ""
                t = {n.text : a }
                expectedOutput[testNum].append(t)
                found_tag += 1
        #print "test %d: " % testNum, expectedOutput[testNum]
        if options.debug: # print out all excepted output
            print "test %d: " % testNum
            for n in expectedOutput[testNum]:
                for t,a in n.iteritems():
                    if a != "":
                        print "   will test for tag: %s with attribute name: %s" %(t, a )
                    else:
                        print "   will test for tag: %s " % (t)

        testNum += 1
        if found_tag < 2:  # if dont find all 3 tags, print error and exit
            print "Error: missing tag in test configuration file ", filename
            sys.exit(-1)

    num_interfaces = 0
    return inputFile, testDescription, expectedOutput, getAllRequest

#######################################################

def pickInterface(filename):
    """ add Comment here
    """
    num_interfaces = 0
    interfaceList = []
    hostList = []
    addrList = []

    try:
        tree = ElementTree.parse(filename)
    except:
        print "Error parsing reply file %s:" % filename
        sys.exit(-1)

    for e in tree.findall("//%sinterface" % NMWGT):
        # look at all children of this element
        found = 0
        for n in e:
            if n.tag.find("ifName") > 0:
                found += 1
                ifName = n.text
            if n.tag.find("hostName") > 0:
                found += 1
                hostName = n.text
            if n.tag.find("ifAddress") > 0:
                found += 1
                ifAddr = n.text
        if found < 3:
            #print "Warning: only found %d of the following: ifName, hostName, ifAddress" % found
            pass
        else: # only add to list of all information is there...
            addrList.append(ifAddr)
            interfaceList.append(ifName)
            hostList.append(hostName)
            num_interfaces += 1
         #   print "Adding to list: ", hostName, ifAddr, ifName

    print "Found %d interfaces" % num_interfaces
    if num_interfaces <= 0:
        print "Error: need at least 1 interface to continue. Exiting..."
        sys.exit(-1)

    # pick one at random
    random.seed()
    rdm = random.randint(0, num_interfaces-1)
    return (hostList[rdm], addrList[rdm], interfaceList[rdm], num_interfaces)

#######################################################

def pickEndPointPair(filename):
    """ add Comment here
    """
    num_pairs = 0
    srcList = []
    dstList = []

    try:
        tree = ElementTree.parse(filename)
    except:
        print "Error parsing reply file %s:" % filename
        sys.exit(-1)

    for e in tree.findall("//%sendPointPair" % NMWGT):
        num_pairs += 1
        for n in e:
            if n.tag.find("src") > 0:
                srcList.append(n)
            if n.tag.find("dst") > 0:
                dstList.append(n)

    print "Found %d endPointPairs" % num_pairs
    if num_pairs <= 0:
        print "Error: need at least 1 endPointPair to continue. Exiting..."
        sys.exit(-1)

    # pick one at random
    random.seed()
    rdm = random.randint(0, num_pairs - 1)
    return (srcList[rdm], dstList[rdm], num_pairs )

#######################################################

def runClient(fd, logfile, service, requestFile):
    """ get data from perfSONAR using the client.pl script
    """

    cmd = client_script + service + " " + requestFile
    data = []
    if verbose > 0:
        print "\nCalling: %s (stderr = %s) \n" % (cmd, logfile)
#    pipe = Popen(cmd, shell=True, stderr=fd, stdout=PIPE).stdout
    pipe = os.popen(cmd)
    d1 = pipe.readlines()
    if verbose > 0:
        print "Query returned %d lines of data" % len(d1)
	print d1
    if len(d1) == 0:
        PS_Error(fd,logfile)
    return (d1)

#######################################################

def replaceElement(tree, tag, newval):
    """ add Comment here
    """
    searchstring = ".//%s%s/" % (NMWGT, tag)
    #print "Searching for: ", searchstring
    try:
        el = tree.findall(searchstring)[0]
    except:
#           print "%s not found " % tag
        pass
    else:
        if verbose > 0:
            print "replacing %s with %s" % (el.text, newval)
        el.text = newval
    return

#######################################################

def replaceKey(tree, tag, saveKey):
    """ add Comment here
    """
    #find the "key" element by tag name
    try:
        e = tree.findall("//%skey" % NMWG)[0]
    except:
        return

    #debug
    #print "found and replaced key element"
    #print "replacement key: "
    #ElementTree.dump(saveKey)

    e.clear()  # clear out old key
    for el in saveKey.getiterator():
        if el.tag != "%skey" % NMWG:  # key tag is still there, so dont add it a 2nd time
           e.append(el)

    #debug
    #print "new request: "
    #ElementTree.dump(tree)
    #print "-------------------------------"

    return

#######################################################

def replaceElementAttribute(tree, tag, aname, newval):
    """ Unfortunately python 2.5's version of elementtree does not
        support xpath queries for attributes, so have to look one by one
    """
    searchstring = ".//%s%s/" % (NMWG, tag)
    try:
        el = tree.findall(searchstring)
    except:
        pass
    else:
        for e in el:
            if e.get("name") == aname:
                if verbose > 0:
                    print "replacing %s with %s" % (e.text, newval)
                e.text = newval
#            else:
#               print "replaceElementAttribute: attr %s not found for tag %s " % (e.get("name"), tag)
    return

######################################################################################
def CheckResult(testNum, expectedOutput, tree):

    global options

    found_result = []
    #print "Test %d: " % testNum, expectedOutput
    num_tests = len(expectedOutput)
    found_result = [0] * num_tests  # intialize to all elements 'not found'
    tnum = 0
    for t in expectedOutput:
        for tag,attr in t.iteritems():
            #print "Test %d: T,A: " % tnum, tag, attr
            for ns  in NMWG_ALL:
                if options.debug:
                    print "    Looking for tag '%s' and attrib '%s' in %s " % (tag, attr, ns)
                elist = tree.findall("//%s%s" % (ns,tag))
                if len(elist) > 0:
                    #if options.debug:
                    #    print "Found %d instances of tag %s" % (len(elist), tag)
                    if attr != "":  # search for attribute too
                        for e in elist:
                            aVal = e.attrib.get(attr)
                            if aVal != None:
                                if options.debug:
                                    if found_result[tnum] == 0: # print this for first item found
                                        print "   Found tag '%s' with attribute '%s': %s" % (tag, attr, aVal)
                                found_result[tnum] += 1
                    else:
                        if options.debug:
                            if found_result[tnum] == 0: # print this for first item found
                                print "   Found tag '%s': %s" % (tag, elist[0].text)
                        found_result[tnum] += len(elist)
            if found_result[tnum] == 0:
                print "   Tag '%s' (attrib: '%s') not found" % (tag,attr)

        tnum += 1

    def f(x): return x
    num_found = len(filter(f,found_result))  # counts the number of array elements > 0
    tot_found = 0
    for n in found_result:
        tot_found += n

    print "   Found %d out of %d expected results (%d items found)" % (num_found,
                len(found_result), tot_found)
    if num_found < len(found_result):
        print "Test Failed! "
        return 0
    else:
        print "Test Passed! "
        return tot_found

#######################################################

def PS_Error(fd, logfname):
    print "Error: no reply from MA"
    fd.close() # flush errors
    fd =  open(logfname)
    d = fd.readlines()
    print d[len(d)-1] # print last line of log file
    return()

#######################################################

def timeIt(*args):
    begin = time.time()
    r = args[0](*args[1:])
    secs = time.time() - begin
    print "TIMING %s: %f" % (args[0].__name__, secs)
    return r, secs

#######################################################

def main():

    global verbose, requestDir, options
    options = getOptions()
    inputFile, testDescription, expectedOutput, getAllRequest = loadTestConfigFile(options.configFile)
    #print inputFile
    #print testDescription
    #print expectedOutput

    # catch stdout of execed programs here
    logfname = "%s/%s.%d.log" % (logdir,os.path.basename(sys.argv[0]), os.getuid())
    fd = open(logfname, 'a')

    if options.csv:
        try:
            csvFile = open(timingResultsFile, "a")
        except:
            print "Error opening file %s " % timingResultsFile
            sys.exit(-1)

    if getAllRequest != "":
        # 1st get list of interfaces
        rf = requestDir + "/" + getAllRequest
        print "Getting list of all Interfaces from the MA at %s using request file: %s " % (options.PS_url, rf)
        data,t = timeIt(runClient,fd,logfname,options.PS_url, rf)
        # save results to file
        resultFile = logdir + os.path.basename(getAllRequest) + ".reply"
        if verbose > 0:
            print "Creating reply file (%d lines of data): %s" % (len(data), resultFile)
        file = open(resultFile, "w")  # updated file with actual data
        file.writelines(data)
        file.close()

        if options.PS_url.find("perfSONARBOUY") > 0:
            src, dst, nr = pickEndPointPair(resultFile)
            print "Using src/dst randomly selected interface: %s/%s : %s/%s" % ( src.attrib.get("value"),
                src.attrib.get("port"), dst.attrib.get("value"), dst.attrib.get("port"))
        else:
            hostName, ifAddr, ifName, nr = pickInterface(resultFile)
            print "Using interface randomly selected interface %s:%s " % (hostName, ifName)

        if options.csv:
            csvFile.write("\n%s\n" % options.PS_url)
	    csvFile.write("TestNum, Timing, DataSize, Description \n\n")
            csvFile.write("%d, %f, %d %s\n" % (1, float(t), nr, "Get All Metadata"))


    save_Key = None   # place to store valid maKey for future tests
    testNum = total_pass = total_fail = 0
    for requestFile in inputFile:
        print "-----------------------------------------"
        print "Testing using file: ", requestFile
        rf = requestDir + "/" + requestFile
        try:
            tree = ElementTree.parse(rf)
        except:
            print "Error parsing request file %s" % rf
            sys.exit(-1)

        now = int(time.time())

        if options.PS_url.find("perfSONARBOUY") > 0:
            replaceElementAttribute(tree, "src", "value", src.attrib.get("value"))
            replaceElementAttribute(tree, "dst", "value", dst.attrib.get("value"))
            replaceElementAttribute(tree, "src", "port", src.attrib.get("port"))
            replaceElementAttribute(tree, "dst", "port", dst.attrib.get("port"))
        elif getAllRequest != "":
            replaceElement(tree, "ifAddress", ifAddr)
            replaceElement(tree, "hostName", hostName)
            replaceElement(tree, "ifName", ifName)

        if options.PS_url.find("perfSONARBOUY") > 0: # XXX: Hack untill have a call to request valid time ranges
                                                     # current perfSONARBOUY test database has 2007 data only
            oneYearAgo = 3600 * 24 * 365
            replaceElementAttribute(tree, "parameter", "startTime", "%s" % (now - oneYearAgo - (3600 * 12)) )  # 1yr + 12 hrs ago
            replaceElementAttribute(tree, "parameter", "endTime", "%s" % (now - oneYearAgo) )
        else:
            replaceElementAttribute(tree, "parameter", "startTime", "%s" % (now - (3600 * 12)) )  # 12 hrs ago
            replaceElementAttribute(tree, "parameter", "endTime", "%s" % (now - 600) )  # 10 min ago
        if save_Key != None:
            replaceKey(tree, "parameter", save_Key)

        #write out the modified XML
        testFile = logdir + os.path.basename(requestFile) + ".test"
        file = open(testFile, "w")  # updated file with actual data
        tree.write(file)
        file.close()

        if verbose > 0:
            print "Running test %d: %s " % (testNum, testDescription[testNum])

        data,t = timeIt(runClient,fd,logfname, options.PS_url, testFile)
        #print "Got reply: %d lines " % len(data)
        # save results to file
        resultFile = logdir + os.path.basename(requestFile) + ".reply"
        file = open(resultFile, "w")  # updated file with actual data
        file.writelines(data)
        file.close()

        # now use xpath to make sure the reply looks OK.
        tree = ElementTree.parse(resultFile)

        if options.debug:
            # print out results
            print "------------------------------------------------------"
            ElementTree.dump(tree)
            print "------------------------------------------------------"

	found_error = 0

        # check for errors
	for e in tree.findall("//%seventType/" % NMWG):
		if e != None and e.text.find("error") >= 0:
	            error = tree.find("//%sdatum/" % NMWGR).text
	            print "Got error message: ", error
	            print "Test Failed!"
		    found_error = 1
		    break

	if found_error == 0:
            result = CheckResult(testNum, expectedOutput[testNum], tree)
	else:
	    result = 0

        if result > 0:
            total_pass += 1
        else:
            total_fail += 1

        if options.csv:
            csvFile.write("%d, %f, %d, %s \n" % (testNum+2, float(t), result, testDescription[testNum]))

        testNum += 1

        if save_Key == None:  # need to find a valid key to use in future requests
	    try:
                e = tree.findall("//%skey" % NMWG)[0]
	    except:
		continue
            save_Key = e[0]  # known good Key: save this to use in a future request
            if options.debug:
                print "Saving this key element for future requests: ", e
                for p in e[0].getiterator():
                    for c in p:
                        print "   ", c.tag, c.text, c.attrib


    print "\nTotal of %d tests passed and %d tests failed. " % (total_pass, total_fail)
    if options.csv:
	print "results can be found in file: ", timingResultsFile
    print "Done."
    sys.exit(1)

if __name__ == "__main__": main()


