#Socket client example in python

import socket #for sockets
import sys #for exit

try:
	#creat an AF_INET, STREAM socket (TCP)
	s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
except socket.error, msg:
	print 'Failed to create socket. Error code: ' + str(msg[0]) + ', Error message : ' + msg[1]
	sys.exit();

print 'Socket Created'

host = 'www.google.com';
port = 80;

try:
	remote_ip = socket.gethostbyname( host )
except socket.gaierror:
	#could not resolve
	print 'Hostname could not be resolved. Exiting'
	sys.exit()

print('Ip address of '+ host + ' is ' + remote_ip)

#connect to remote server
s.connect((remote_ip, port))

print('Socket Connected to ' + host + ' on ip ' + remote_ip)

#Send some data to remote server
message = "GET / HTTP/1.1\r\n\r\n"

try:
	#Set the whole string
	s.sendall(message)
except socket.error:
	#Send failed
	print 'Send Failed'
	sys.exit()
print 'Message sent successfuly'

#Now recieve data
reply = s.recv(4096)

print reply

#close the socket
s.shutdown(1); s.close()
