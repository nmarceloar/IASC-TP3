

defmodule ChatServer do 

	def new do
		spawn(fn -> loop(0, Map.new, Map.new) end)
	end

	def loop(msgid, messages, clients) do
		
		receive do

			{:connect, sender} -> 
				send sender, {:connect_ack, self()}
				loop(msgid, messages, Map.put(clients, sender, MapSet.new))

			{:silence, sender, to_be_silenced} -> 
				loop(msgid, messages, Map.put(clients, sender, 
						MapSet.put(Map.get(clients, sender), to_be_silenced)))

			{:unsilence, sender, to_be_unsilenced} -> 
				loop(msgid, messages, Map.put(clients, sender,
						MapSet.delete(Map.get(clients, sender), to_be_unsilenced)))

			{:unicast, sender, destination, {localid, msg}} ->
				send(destination, {:new_unicast, self(), {msgid+1,msg}})
				loop(msgid+1, Map.put(messages, msgid + 1, {sender, localid, msg}), clients)

			{:unicast_received, sender, global_id} ->
				{sender_id, localid, msg} = Map.get(messages, global_id)
				send sender_id, {:unicast_received, self(), localid}
				loop(msgid, messages, clients)

			{:unicast_read, sender, global_id} ->
				{sender_id, localid, msg} = Map.get(messages, global_id)
				send sender_id, {:unicast_read, self(), localid}
				loop(msgid, messages, clients)

			{:broadcast, sender, msg} ->
				Enum.each(
					MapSet.difference(
						MapSet.new(List.delete(Map.keys(clients), sender)), 
						Map.get(clients, sender)), 
					fn client -> send client, {:new_broadcast, self(), msg} end)
				loop(msgid, messages, clients)

			{:dump_clients} -> 
				Enum.each(Map.keys(clients), fn c -> IO.puts(inspect c) end)
				loop(msgid, messages, clients)

			{:dump_silenced} -> 
				Enum.each(clients, fn s -> IO.puts(inspect s) end)
				loop(msgid, messages, clients)

		end

	end

	def clients(server) do
		send server, {:dump_clients}
	end 

	def silenced(server) do
		send server, {:dump_silenced}
	end 

end



defmodule ChatClient do 

	def new(server) do 
		spawn(fn -> init(server) end)
	end 

	def init(server) do
		send server, {:connect, self}
		receive do 
			{:connect_ack, ^server} -> 
				IO.puts "#{inspect self} is now connected to #{inspect server}"
				loop(server, Map.new, 0)
		end 
	end 
	
	def loop(server, messages, localid) do

		receive do 

			{:silence, to_be_silenced} ->
				send(server, {:silence, self(), to_be_silenced})
				loop(server, messages, localid)

			{:unsilence, to_be_unsilenced} ->
				send(server, {:silence, self(), to_be_unsilenced})
				loop(server, messages, localid)

			{:dump_messages} -> 
				Map.values(messages) |> Enum.each(fn msg -> IO.puts(inspect msg) end)
				loop(server, messages, localid)

			{:send_unicast, destination, msg} -> 
				IO.puts("#{inspect self} sent unicast message with localid: #{localid+1}")
				send(server, {:unicast, self(), destination, {localid + 1, msg}})
				loop(server, Map.put(messages, localid+1, {msg, false, false}), localid + 1)

			{:unicast_received, ^server, localid} -> 
				IO.puts "#{inspect self} received notification: -- Receiver confirmed reception of msg_id: #{localid}  --"
				{msg, received, read} = Map.get(messages, localid)
				loop(server, Map.put(messages, localid, {msg, true, read}), localid)

			{:unicast_read, ^server, localid} -> 
				IO.puts "#{inspect self} received notification: -- Receiver has read msg_id: #{localid} --"
				{msg, received, read} = Map.get(messages, localid)
				loop(server, Map.put(messages, localid, {msg, received, true}), localid)

			{:send_broadcast, msg} -> 
				send(server, {:broadcast, self(), msg})
				loop(server, messages, localid)

			{:new_unicast, ^server, {msg_id, msg}} -> 
				IO.puts "#{inspect self} received new unicast msg --> #{msg}"
				send(server, {:unicast_received, self(), msg_id})
				:timer.send_after(randomdelay(), self(), {:read_unicast, msg_id})
				loop(server, messages, localid)

			{:new_broadcast, ^server, msg} -> 
				IO.puts "#{inspect self} received broadcast -- #{msg} --"
				loop(server, messages, localid)

			{:read_unicast, msg_id} -> 
				send(server, {:unicast_read, self(), msg_id})
				loop(server,messages, localid)

		end 

	end


	def random(min,max) do
		Kernel.trunc(min + Float.floor(:random.uniform * (max - min)))
	end

	def randomdelay() do
		random(3000,5000)
	end

	def send_unicast(client, destination, msg) do
		send client, {:send_unicast, destination, msg}
	end

	def send_broadcast(client, msg) do
		send client, {:send_broadcast, msg}
	end

	def silence(client, to_be_silenced) do
		send(client, {:silence, to_be_silenced})
	end

	def unsilence(client, to_be_unsilenced) do
		send(client, {:unsilence, to_be_unsilenced})
	end

	def messages(client) do
		send client, {:dump_messages}
	end

end 



# ---- TESTs (si se les puede llamar tests) -----

s = ChatServer.new 

c1 = ChatClient.new(s)
c2 = ChatClient.new(s)
c3 = ChatClient.new(s)
c4 = ChatClient.new(s)
c5 = ChatClient.new(s)

# server deberia conocer a los 5 clientes

ChatServer.clients(s)

# server no deberia tener ningun cliente silenciado

ChatServer.silenced(s)

# c2, c3, c4, y c5 deberian recibir los broadcasts de c1

ChatClient.send_broadcast(c1, "broadcast from c1")

# c2 deberia recibir los unicast de c1

ChatClient.send_unicast(c1, c2, "unicast from c1 to c2")

# c2 y c3 no deberian ver los broadcasts de c1 despues de ser silenciados para c1

ChatClient.silence(c1, c2)
ChatClient.silence(c1, c3)

ChatServer.silenced(s)

ChatClient.send_broadcast(c1, "broadcast from c1")

# c2 y c3 deberian ver nuevamente los broadcasts de c1 luego de ser activados nuevamente

ChatClient.unsilence(c1, c2)
ChatClient.unsilence(c1, c3)

ChatClient.send_broadcast(c1, "broadcast from c1")

# c3, c4, y c5 deberian recibir los unicast de c1 confirmado recepcion y lectura por separado

ChatClient.send_unicast(c1, c3, "unicast from c1 to c3")
ChatClient.send_unicast(c1, c4, "unicast from c1 to c4")
ChatClient.send_unicast(c1, c5, "unicast from c1 to c5")
