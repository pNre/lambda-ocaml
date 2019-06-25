FROM ocaml/opam2:ubuntu-18.04-ocaml-4.07
RUN cd /home/opam/opam-repository/
RUN git pull
WORKDIR /app
RUN sudo chown -R opam:nogroup .
RUN opam update
RUN opam upgrade -y
RUN opam install -y dune
RUN eval `opam config env`
RUN opam depext async core cohttp-async ppx_deriving yojson
RUN opam pin https://github.com/inhabitedtype/httpaf.git
RUN opam install -y async core cohttp-async ppx_deriving yojson
COPY --chown=opam:nogroup . /app
RUN rm main.exe || true
RUN opam config exec -- dune build main.exe --profile=static
RUN gcc -shared -fPIC -ldl -o hook.so hook.c
RUN mv _build/default/main.exe main.exe
