FROM ocaml/opam2:ubuntu-18.04-ocaml-4.07
RUN cd /home/opam/opam-repository/
RUN git pull
WORKDIR /app
RUN sudo chown -R opam:nogroup .
RUN opam update
RUN opam upgrade -y
RUN opam install -y dune
RUN eval `opam config env`
RUN opam depext async cohttp-async ppx_deriving ppx_deriving_yojson yojson
RUN opam install -y async cohttp-async ppx_deriving ppx_deriving_yojson yojson
COPY --chown=opam:nogroup . /app
RUN rm main.exe || true
RUN opam config exec -- dune build main.exe --profile=static
RUN gcc -shared -fPIC -ldl -o hook.so hook.c
RUN mv _build/default/main.exe main.exe
