
with Componolit.Gneiss.Types;
with Componolit.Gneiss.Component;

package Component with
   SPARK_Mode
is

   package Cai renames Componolit.Gneiss;

   procedure Construct (C : Cai.Types.Capability);
   procedure Destruct;

   package Main is new Cai.Component (Construct, Destruct);

end Component;
