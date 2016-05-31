#Socket client in python by daBlaqSuit!!

import SocketServer #SocketServer Package
import socket #for sockets
import time #for time
import sys #for exit

try:
	#creat an AF_INET, STREAM socket (TCP)
	s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

except socket.error, msg:
	print 'Failed to create socket. Error code: ' + str(msg[0]) + ', Error message : ' + msg[1]
	sys.exit();

print 'Socket Created'

host = 'daBlaqChat';
port = 8085;

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
session = s.recv(2048)
print session

while 1:
 
	data = s.recv(2048)
	print data
	if not data:
		break

	data = raw_input(" You: " )
	s.sendall(data)
	if data == "exit":
		reply = s.recv(2048)
		sys.exit('You left the daBlaqChat')

		#print 'message sent...'
		#s.sendall(data)

s.close()
