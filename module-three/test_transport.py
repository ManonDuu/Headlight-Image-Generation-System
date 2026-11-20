import subprocess,unittest
from pathlib import Path
from unittest.mock import patch
from providers.transport import post_once
from providers.gemini import GeminiProvider
class TransportChecks(unittest.TestCase):
 def test_partial_response_is_not_retried_or_accepted(self):
  def partial(command,**kwargs):
   Path(command[command.index('--output')+1]).write_bytes(b'partial')
   return subprocess.CompletedProcess(command,18,b'{"httpStatus":200}',b'')
  diagnostic={}
  with patch('providers.transport.subprocess.run',side_effect=partial) as call:
   with self.assertRaisesRegex(RuntimeError,'传输中断'):post_once('https://example.com',b'{}','test',diagnostic)
   self.assertEqual(call.call_count,1)
   self.assertIn('--http1.1',call.call_args.args[0])
   self.assertEqual(diagnostic['responseBytes'],7)
   self.assertEqual(diagnostic['curlExitCode'],18)
 def test_failure_diagnostics_survive_provider(self):
  def fail(endpoint,body,key,diagnostic):
   diagnostic.update(curlExitCode=18,responseBytes=7)
   raise RuntimeError('传输中断')
  with patch('providers.gemini.post_once',side_effect=fail):
   with self.assertRaises(RuntimeError) as error:
    GeminiProvider('test').generate({'prompt':'test','ratio':'1:1'},[],{'reserveUSD':.5})
   self.assertEqual(error.exception.diagnostic['curlExitCode'],18)

class TimeoutChecks(unittest.TestCase):
 def test_zero_http_status_does_not_destroy_timing_diagnostics(self):
  response=subprocess.CompletedProcess([],28,b'httpStatus=000\nconnectSeconds=0.001\ntlsSeconds=0.000\nfirstResponseSeconds=0.000\ntotalSeconds=45.001\nuploadedBytes=0\n',b'')
  d={}
  with patch('providers.transport.subprocess.run',return_value=response) as call:
   with self.assertRaisesRegex(RuntimeError,'安全连接'):post_once('https://example.com',b'{}','test',d)
   self.assertEqual(d['phase'],'connection-timeout');self.assertEqual(d['httpStatus'],0);self.assertEqual(d['totalSeconds'],45.001)
   args=call.call_args.args[0];self.assertEqual(args[args.index('--connect-timeout')+1],'45');self.assertEqual(call.call_count,1)
 def test_response_timeout_retains_uncertainty(self):
  d={};r=subprocess.CompletedProcess([],28,b'httpStatus=000\ntlsSeconds=1.2\nuploadedBytes=200\ntotalSeconds=240\n',b'')
  with patch('providers.transport.subprocess.run',return_value=r):
   with self.assertRaisesRegex(RuntimeError,'计费未知'):post_once('https://example.com',b'{}','test',d)
  self.assertEqual(d['phase'],'response-timeout')
 def test_subprocess_timeout_is_reported_without_retry(self):
  d={}
  with patch('providers.transport.subprocess.run',side_effect=subprocess.TimeoutExpired('curl',250)) as call:
   with self.assertRaisesRegex(RuntimeError,'进程超时'):post_once('https://example.com',b'{}','test',d)
   self.assertEqual(call.call_count,1);self.assertEqual(d['phase'],'transport-process-timeout')

class BillingChecks(unittest.TestCase):
 def test_payment_rejection_is_explicit_and_not_retried(self):
  d={};r=subprocess.CompletedProcess([],0,b'httpStatus=402\ntlsSeconds=0.5\nuploadedBytes=200\ntotalSeconds=32\n',b'')
  with patch('providers.transport.subprocess.run',return_value=r) as call:
   with self.assertRaisesRegex(RuntimeError,'计费状态异常'):post_once('https://example.com',b'{}','test',d)
   self.assertEqual(call.call_count,1)
  self.assertEqual(d['failureCategory'],'billing');self.assertFalse(d['retryable'])
