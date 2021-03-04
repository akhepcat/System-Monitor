#!/usr/bin/python3
""" 
This will connect to either the specified mail server on the specified port;
or
 it will attempt to auto-determine the local domainname and local MX server

it will return the number of ms required to get a response from the server.
"""
import smtplib, ssl, time, socket, sys, getopt, dns.resolver

def usage():
  print('smtp-response-test -h [-s ,--server=]host [-p ,--port=]port')
  print('    host:   hostname to check (mail.example.com)')
  print('    port:   service port (25, 465, 587, etc)')
  print('')
  print(' returns:   milliseconds to receive response from server')

def mailtest(smtp_server, port, context):
    """testing the mailserver"""
    timeout = 10

    if (port == 465):
      try:
        with smtplib.SMTP_SSL(host=smtp_server, port=port, timeout=timeout, context=context) as server:
#            server.set_debuglevel(1)
            server.ehlo()  # This is usually automatic by 'sendmail' but we call it for has_extn early
            if(server.has_extn('PIPELINING')):
               pipeline=1
            server.quit()
      except Exception as e:
        print('exception occured: {0}'.format(e))

    else:
      try:
        with smtplib.SMTP(host=smtp_server, port=port, timeout=timeout) as server:
#            server.set_debuglevel(1)
            server.ehlo()  # This is usually automatic by 'sendmail' but we call it for has_extn early
            if(server.has_extn('PIPELINING')):
               pipeline=1
            if(server.has_extn('starttls')):
               server.starttls(context=context)
            server.ehlo()  # re-identify after starttls
            server.quit()

      except Exception as e:
        print('exception occured: {0}'.format(e))


def mydomainname():
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  s.connect(("8.8.8.8", 53))		# look, ma, we're a TCP DNS query! (but not really)
  myip = s.getsockname()[0]
  s.close()
  hostname, domain = socket.gethostbyaddr(myip)[0].partition('.')[::2]
  return(domain)

def mxchange(domain):
  try:
    res=dns.resolver.resolve(domain, 'mx')
  except:
    mx=''
  else:
    mx=(res[0].exchange.to_text())
    mx = mx.rstrip('.')
  return(mx)
  
#######################
def main(argv):

  try:
    opts, args = getopt.getopt(argv, "hs:p:",["server=","port="])
  except getopt.GetoptError:
    usage()
    sys.exit(2)

  for opt, arg in opts:
    if opt == '-h':
      usage()
      sys.exit()
    elif opt in ("-s", "--server"):
      smtp_server = str(arg)
    elif opt in ("-p", "--port"):
      port = int(arg)

  port = 25;

  dom=mydomainname()
  smtp_server = mxchange(dom)

  if (not smtp_server):
    print("Can't automatically determine MX, specify with args.")
    usage()
    sys.exit(1)

  try:
    smtp_ip = socket.getaddrinfo(smtp_server, None)[0][4][0]
  except:
    smtp_ip = socket.getaddrinfo(smtp_server, None, socket.AF_INET6)[0][4][0]

  context = ssl.create_default_context()

  start = time.time_ns()
  mailtest(smtp_server, port, context)
  stop = time.time_ns()
  duration=(stop - start)/1000000
  print("{0:.0f}".format( duration) )


if __name__ == "__main__":
  main(sys.argv[1:])
