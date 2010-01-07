#!/usr/bin/env python

from distutils.core import setup

setup(name='perfsonar',
      version='0.1',
      description='perfSONAR-PS Python interface',
      author='Monte Goode',
      author_email='mmgoode@lbl.gov',
      url='http://code.google.com/p/perfsonar-ps/',
      packages=['perfsonar'],
      install_requires=['lxml','soaplib'],
      entry_points = {
        }
     )
