"""P1.1 - Medir la capacidad de UNA instancia.

Antes: dejar el autoscale en minimo = maximo = 1 (temporalmente):
  terraform apply -var min_instances=1 -var max_instances=1 ...
Sube 2 usuarios cada 60 s hasta 60. Observe el escalon donde el p95 de /work supera
1 s (interfaz web o CSV): los RPS del escalon ANTERIOR son la capacidad maxima sostenible.
Referencia de la demo: 1 vCPU y /work?ms=150 -> ~6-7 peticiones/s por instancia.

  locust -f tests/locustfile_capacidad.py --host http://<IP_LB> --headless \
         --csv evidencias/p1/capacidad --csv-full-history \
         --html evidencias/p1/capacidad.html
Detenga con Ctrl+C cuando el p95 supere 1 s de forma sostenida (las VM serie B
tienen creditos de CPU: no deje la prueba sin supervision).
"""
import os

from locust import HttpUser, LoadTestShape, between, task

TRABAJO_MS = int(os.environ.get("TRABAJO_MS", "150"))


class Comprador(HttpUser):
    wait_time = between(0.5, 1.5)

    @task
    def trabajo(self):
        self.client.get(f"/work?ms={TRABAJO_MS}", name="/work")


class Escalones(LoadTestShape):
    paso_usuarios = 2
    segundos_por_paso = 60
    maximo_usuarios = 60

    def tick(self):
        paso = int(self.get_run_time() // self.segundos_por_paso) + 1
        usuarios = paso * self.paso_usuarios
        if usuarios > self.maximo_usuarios:
            return None
        return usuarios, self.paso_usuarios
