schtasks.exe /delete /TN "Shutdown on idle" /f

schtasks.exe /create /TN "Shutdown on idle" /XML "C:\Shutdown on idle.xml"