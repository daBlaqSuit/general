import socket
import select

# creating a chat application using python, hope it works... 
# date: 10/05/2016 /was created
# Edited 25/05/2016

class ChatServer:
	

	def __init__( self, port ):
		host = ''
		self.port = port;
		
		self.s = socket.socket( socket.AF_INET, socket.SOCK_STREAM )
		self.s.setsockopt( socket.SOL_SOCKET, socket.SO_REUSEADDR, 1 )
		self.s.bind( (host, port) )
		self.s.listen( 10 )
		
		self.sinput = [self.s]
		print 'ChatServer started on port %s' % port
		
	def run( self ):
			
		while 1:
		#Await an event on a readable socket descriptors
			(sread, swrite, sexc) = select.select( self.sinput, [], [] )
		    # Iterate through the tagged read descriptors
			for sock in sread:
			
			# Received a connect to the server (listening) socket
				if sock == self.s:
					self.accept_new_connection()

				
				#else:
				
			# Received something on a client socket
				#	data = sock.recv(2048)
					
			
			# Check to see if the peer socket closed

				#if data == "exit":
				#	host,port = sock.getpeername()
				#	data = 'Client left %s:%s\r\n' % (host, port)
				
				#	self.broadcast_string( data, sock )
				#	sock.close
				#	self.sinput.remove(sock)
				else:
					data = sock.recv(2048)
					host,port = sock.getpeername()
					newdata = '[%s:%s] %s' % (host, port, data)
					self.broadcast_string( newdata, sock )
				
	def broadcast_string( self, data, omit_sock ):
		for sock in self.sinput:
			if sock != self.s and sock != omit_sock:
				sock.send(data)

		print data;
	def accept_new_connection( self):
		conn, addr = self.s.accept()
		self.sinput.append( conn )

		conn.send("You're connected to the Python chatserver\r\n")
		data = 'Client joined %s:%s\r\n' % addr
		self.broadcast_string( data, conn )

myserver = ChatServer(8085).run()
