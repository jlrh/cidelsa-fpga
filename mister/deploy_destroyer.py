#!/usr/bin/env python3
"""Redeploy Destroyer core+mra to the MiSTer boards after a Quartus build.

Uso:  python deploy_destroyer.py
Sube output_files/Destroyer.rbf y Destroyer.mra a ambas placas por SFTP,
verifica el tamano remoto, hace sync y dispara reload no destructivo.
"""
import os
import sys
import paramiko

HOSTS = ["192.168.5.123", "192.168.5.88"]
BASE = os.path.dirname(os.path.abspath(__file__))
RBF = os.path.join(BASE, "output_files", "Destroyer.rbf")
MRA = os.path.join(BASE, "Destroyer.mra")

FILES = [
    (RBF, "/media/fat/_Arcade/cores/Destroyer.rbf"),
    (MRA, "/media/fat/_Arcade/Destroyer.mra"),
]


def main():
    if not os.path.exists(RBF):
        sys.exit(f"ERROR: no existe {RBF} -- el build no ha terminado o fallo.")
    print(f"Local  Destroyer.rbf = {os.path.getsize(RBF)} bytes")
    for host in HOSTS:
        try:
            c = paramiko.SSHClient()
            c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            c.connect(host, username="root", password="1", timeout=25,
                      look_for_keys=False, allow_agent=False)
            sftp = c.open_sftp()
            for lp, rp in FILES:
                sftp.put(lp, rp)
                print(f"  {host} {os.path.basename(lp):16s} -> {sftp.stat(rp).st_size} bytes")
            sftp.close()
            c.exec_command("sync")
            c.close()
            print(f"  {host} OK")
        except Exception as e:
            print(f"  {host} FALLO: {e}")


if __name__ == "__main__":
    main()
