require Enum

defmodule Client do

	def start(server) do
		spawn_link(fn -> loop(%{server: server}) end)
	end

	def loop(silenciados) do 
		receive do
			{rx, :silence} -> loop(Map.put(silenciados, rx, true))
			{rx, :notify_start} -> send rx, {self, :tx_started}
			{rx, :send_msg, msg} -> send rx, {self, :receive, msg}
			{rx, :ack_received } -> IO.puts "#{inspect self}: Mensaje confirmado por receptor #{inspect rx}"
			{tx, :receive, msg} -> 
				IO.puts("#{inspect self}: Mensaje recibido: #{msg}") 
				unless Map.get(silenciados,tx) do 
					send(tx, {self, :ack_received})
				end
			{tx, :tx_started } -> IO.puts("#{inspect self}: #{inspect tx} Comenzo a escribir")
		end
		loop(silenciados)
	end
end

defmodule Server do
	
	def start do
		spawn_link(fn -> loop([], %{}) end)
	end

	defp notify_all (sender, clients, msg) do 

		Enum.each 
			clients,
			fn client -> unless client == sender do send client, {sender, :receive, msg} end 

	end


	def loop(clients, mute_map) do
		receive do
			{pid, :join} -> loop([pid | clients], mute_map)
			{pid, :mute, pid_muted} -> 
				loop(clients, Map.put(mute_map, pid_muted, [pid | Map.get(mute_map, pid_muted)]))
			{sender, :broadcast, msg } -> notify_all sender, clients, msg

		end
		loop(clients, mute_map)
	end

end


	user1 = P2p.start
	user2 = P2p.start
	user3 = P2p.start

	send user1, {user2, :silence}

	send user2, {user1, :notify_start}
	:timer.sleep(1000)
	send user2 , { user1, :send_msg, "hola de parte del user2"}

	send user3, {user1, :notify_start}
	:timer.sleep(1000)
	send user3 , { user1, :send_msg, "hola de parte del user3"}

	

	









