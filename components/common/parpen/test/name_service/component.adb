with Gneiss.Log.Client;
with Gneiss.Message.Client;
with Gneiss.Memory.Client;

with Parpen.Generic_Types;
with Parpen.Protocol.Generic_Reply;
with Parpen.Protocol.Generic_Request;
with Parpen.Protocol.Generic_Transaction;
with Parpen.Protocol.Generic_Contains;

with Parpen.Container;

package body Component with
   SPARK_Mode
is

   subtype Message_Buffer is String (1 .. 128);
   Null_Buffer : constant Message_Buffer := (others => ASCII.NUL);
   type String_Ptr is access all String;
   type Bit_Length is range 0 .. Natural'Last * 8;

   package Types is new Parpen.Generic_Types (Index      => Positive,
                                              Byte       => Character,
                                              Bytes      => String,
                                              Bytes_Ptr  => String_Ptr,
                                              Length     => Natural,
                                              Bit_Length => Bit_Length);

   package Reply_Package is new Parpen.Protocol.Generic_Reply (Types);
   package Request_Package is new Parpen.Protocol.Generic_Request (Types);
   package Transaction_Package is new Parpen.Protocol.Generic_Transaction (Types);
   package Contains_Package is new Parpen.Protocol.Generic_Contains (Types, Request_Package, Transaction_Package);

   procedure Event;

   package Message is new Gneiss.Message (Message_Buffer, Null_Buffer);
   package Message_Client is new Message.Client (Event);

   package Memory is new Gneiss.Memory (Character, Positive, String);
   procedure Modify (Session : in out Memory.Client_Session;
                     Data    : in out String);
   package Memory_Client is new Memory.Client (Modify);

   Cap : Gneiss.Capability;
   Log : Gneiss.Log.Client_Session;
   Msg : Message.Client_Session;
   Mem : Memory.Client_Session;

   package FSM is
      procedure Reset;
      procedure Next;
   end FSM;

   package body FSM is

      type State_Type is (Initial, Reply, Final, Fail);
      State : State_Type := Initial;

      procedure Handle_Initial (State : in out State_Type)
      is
         package Request is new Parpen.Container (Types, Message_Buffer'Length);
         Request_Context : Request_Package.Context := Request_Package.Create;
         Transaction_Context: Transaction_Package.Context := Transaction_Package.Create;
      begin
         Request.Ptr.all := (others => ASCII.NUL);
         Request_Package.Initialize (Request_Context, Request.Ptr);
         Request_Package.Set_Tag (Request_Context, Parpen.Protocol.REQUEST_TRANSACTION);
         Contains_Package.Switch_To_Data (Request_Context, Transaction_Context);
         Transaction_Package.Set_Handle (Transaction_Context, 0);

         Transaction_Package.Take_Buffer (Transaction_Context, Request.Ptr);
         Message_Client.Write (Msg, Request.Ptr.all);
         State := Reply;
      end Handle_Initial;

      procedure Handle_Reply (State : in out State_Type)
      is
         use type Parpen.Protocol.Reply_Tag;
         package Reply is new Parpen.Container (Types, Message_Buffer'Length);
         Context : Reply_Package.Context := Reply_Package.Create;
      begin
         if not Message.Initialized (Msg)
         then
            return;
         end if;

         if not Message_Client.Available (Msg) then
            State := Fail;
         end if;

         Message_Client.Read (Msg, Reply.Ptr.all);
         Reply_Package.Initialize (Context, Reply.Ptr);
         Reply_Package.Verify_Message (Context);
         if not Reply_Package.Valid_Message (Context) then
            State := Fail;
            if Gneiss.Log.Initialized (Log) then
               Gneiss.Log.Client.Error (Log, "Invalid reply");
            end if;
            return;
         end if;

         if Reply_Package.Get_Tag (Context) = Parpen.Protocol.REPLY_ERROR
         then
            State := Fail;
            if Gneiss.Log.Initialized (Log) then
               Gneiss.Log.Client.Info (Log, "Error detected");
            end if;
            return;
         end if;

         State := Final;
      end Handle_Reply;

      procedure Handle_Final (State : in out State_Type)
      is
         pragma Unreferenced (State);
      begin
         Main.Vacate (Cap, Main.Success);
      end Handle_Final;

      procedure Handle_Fail (State : in out State_Type)
      is
         pragma Unreferenced (State);
      begin
         Main.Vacate (Cap, Main.Failure);
      end Handle_Fail;

      procedure Reset is
      begin
         State := Initial;
      end Reset;

      procedure Next is
      begin
         case State is
            when Initial => Handle_Initial (State);
            when Reply   => Handle_Reply (State);
            when Final   => Handle_Final (State);
            when Fail    => Handle_Fail (State);
         end case;
      end Next;

   end FSM;

   ---------------
   -- Construct --
   ---------------

   procedure Construct (Capability : Gneiss.Capability)
   is
      -- FIXME: Generate label
      Label : constant String := ASCII.ESC & "prpn" & ASCII.NUL;
   begin
      Cap := Capability;
      Gneiss.Log.Client.Initialize (Log, Cap, "name_service_test");

      Message_Client.Initialize (Msg, Cap, Label);
      if not Message.Initialized (Msg) then
         if Gneiss.Log.Initialized (Log) then
            Gneiss.Log.Client.Info (Log, "Error initializing message session");
         end if;
         Main.Vacate (Cap, Main.Failure);
         return;
      end if;

      Memory_Client.Initialize (Mem, Cap, Label, 4096);
      if not Memory.Initialized (Mem) then
         if Gneiss.Log.Initialized (Log) then
            Gneiss.Log.Client.Info (Log, "Error initializing memory session");
         end if;
         Main.Vacate (Cap, Main.Failure);
         return;
      end if;

      Gneiss.Log.Client.Info (Log, "Initialized");
      FSM.Reset;
      FSM.Next;
   end Construct;

   -----------
   -- Event --
   -----------

   procedure Event
   is
   begin
      FSM.Next;
   end Event;

   ------------
   -- Modify --
   ------------

   procedure Modify (Session : in out Memory.Client_Session;
                     Data    : in out String)
   is
   begin
      null;
   end Modify;

   --------------
   -- Destruct --
   --------------

   procedure Destruct
   is
   begin
      if Gneiss.Log.Initialized (Log) then
         Gneiss.Log.Client.Info (Log, "Destructing...");
      end if;
      Gneiss.Log.Client.Finalize (Log);
   end Destruct;

end Component;
