// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract BovedaDelTesoro {
    address public owner;
    mapping(address => bool) public walletsAutorizadas;
    mapping(address => uint256) public balances;
    mapping(uint256 => Propuesta) public propuestas;
    uint256 public contadorPropuestas;
    uint256 public contadorWallets = 0;
    uint256 public propuestasActivas = 0;

    uint256 public constant TARIFA_ENTRADA = 0.1 ether;
    uint256 public constant LIMITE_WALLETS = 3333;
    uint256 public constant PERIODO_VOTACION = 7 days; // 7 días para votar
    uint256 public constant MAX_PROPUESTAS_ACTIVAS = 3;

    struct Propuesta {
        address proponente;
        TipoPropuesta tipo;
        address token;
        uint256 cantidad;
        address destino;
        uint256 votosAFavor;
        uint256 votosEnContra;
        bool ejecutada;
        uint256 timestamp;
    }

    enum TipoPropuesta {
        CompraVentaERC20,
        CompraVentaERC721,
        TransferenciaERC20,
        TransferenciaERC721
    }

    modifier soloOwner() {
        require(
            msg.sender == owner,
            "Solo el duenno puede ejecutar esta funcion"
        );
        _;
    }

    modifier soloWalletAutorizada() {
        require(walletsAutorizadas[msg.sender], "No estas autorizado");
        _;
    }

    modifier propuestaActiva(uint256 _idPropuesta) {
        require(
            block.timestamp <=
                propuestas[_idPropuesta].timestamp + PERIODO_VOTACION,
            "El periodo de votacion ha terminado"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function unirseAlContrato() public payable {
        require(
            msg.value == TARIFA_ENTRADA,
            "Debes pagar la tarifa de entrada"
        );
        require(!walletsAutorizadas[msg.sender], "Ya te has unido al contrato");
        require(
            contadorWallets < LIMITE_WALLETS,
            "Se ha alcanzado el limite de wallets"
        );

        walletsAutorizadas[msg.sender] = true;
        contadorWallets++;
        payable(owner).transfer(TARIFA_ENTRADA);
    }

    function proponerVotacion(
        TipoPropuesta _tipo,
        address _token,
        uint256 _cantidad,
        address _destino
    ) public soloWalletAutorizada {
        require(
            propuestasActivas < MAX_PROPUESTAS_ACTIVAS,
            "Hay demasiadas propuestas activas"
        );

        Propuesta memory nuevaPropuesta = Propuesta({
            proponente: msg.sender,
            tipo: _tipo,
            token: _token,
            cantidad: _cantidad,
            destino: _destino,
            votosAFavor: 0,
            votosEnContra: 0,
            ejecutada: false,
            timestamp: block.timestamp
        });

        propuestas[contadorPropuestas] = nuevaPropuesta;
        contadorPropuestas++;
        propuestasActivas++;
    }

    function votar(
        uint256 _idPropuesta,
        bool _aFavor
    ) public soloWalletAutorizada propuestaActiva(_idPropuesta) {
        require(
            !propuestas[_idPropuesta].ejecutada,
            "La propuesta ya fue ejecutada"
        );
        // Aquí deberías implementar lógica para evitar votos duplicados

        if (_aFavor) {
            propuestas[_idPropuesta].votosAFavor++;
        } else {
            propuestas[_idPropuesta].votosEnContra++;
        }
    }

    function ejecutarPropuesta(
        uint256 _idPropuesta
    ) public soloWalletAutorizada {
        Propuesta storage prop = propuestas[_idPropuesta];
        require(!prop.ejecutada, "La propuesta ya fue ejecutada");
        require(
            prop.votosAFavor > prop.votosEnContra,
            "La propuesta no fue aprobada"
        );
        require(
            block.timestamp > prop.timestamp + PERIODO_VOTACION,
            "El periodo de votacion aun no ha terminado"
        );

        if (prop.tipo == TipoPropuesta.CompraVentaERC20) {
            // Lógica para comprar/vender ERC-20
        } else if (prop.tipo == TipoPropuesta.CompraVentaERC721) {
            // Lógica para comprar/vender ERC-721
        } else if (prop.tipo == TipoPropuesta.TransferenciaERC20) {
            IERC20(prop.token).transfer(prop.destino, prop.cantidad);
        } else if (prop.tipo == TipoPropuesta.TransferenciaERC721) {
            IERC721(prop.token).transferFrom(
                address(this),
                prop.destino,
                prop.cantidad
            );
        }

        prop.ejecutada = true;
        propuestasActivas--;
    }

    function retirarETH(uint256 _cantidad) public soloWalletAutorizada {
        require(balances[msg.sender] >= _cantidad, "Fondos insuficientes");
        balances[msg.sender] -= _cantidad;
        payable(msg.sender).transfer(_cantidad);
    }
}
