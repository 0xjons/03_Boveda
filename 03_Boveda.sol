// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BovedaDelTesoro is ReentrancyGuard {
    address public owner;
    //mapping(address => bool) public walletsAutorizadas;
    WalletAutorizada[] walletsAutorizadas;
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
        mapping(address => bool) haVotado;
    }

    struct WalletAutorizada {
        address wallet;
        bool isAuth;
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
        require(isAuthorized(msg.sender), "No estas autorizado");
        _;
    }

    function isAuthorized(address _wallet) public view returns (bool) {
        for (uint256 i = 0; i < walletsAutorizadas.length; i++) {
            if (
                walletsAutorizadas[i].wallet == _wallet &&
                walletsAutorizadas[i].isAuth
            ) {
                return true;
            }
        }
        return false;
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
        require(!isAuthorized(msg.sender), "Ya te has unido al contrato");
        require(
            contadorWallets < LIMITE_WALLETS,
            "Se ha alcanzado el limite de wallets"
        );

        WalletAutorizada memory nuevaWallet;
        nuevaWallet.wallet = msg.sender;
        nuevaWallet.isAuth = true;
        walletsAutorizadas.push(nuevaWallet);
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

        // Crear una nueva propuesta directamente en el mapping de propuestas
        Propuesta storage nuevaPropuesta = propuestas[contadorPropuestas];

        // Inicializar los campos de la propuesta
        nuevaPropuesta.proponente = msg.sender;
        nuevaPropuesta.tipo = _tipo;
        nuevaPropuesta.token = _token;
        nuevaPropuesta.cantidad = _cantidad;
        nuevaPropuesta.destino = _destino;
        nuevaPropuesta.votosAFavor = 0;
        nuevaPropuesta.votosEnContra = 0;
        nuevaPropuesta.ejecutada = false;
        nuevaPropuesta.timestamp = block.timestamp;

        // Incrementar el contador de propuestas y propuestas activas
        contadorPropuestas++;
        propuestasActivas++;
    }

    function votar(
        uint256 _idPropuesta,
        bool _aFavor
    ) public soloWalletAutorizada propuestaActiva(_idPropuesta) {
        Propuesta storage propuesta = propuestas[_idPropuesta];

        // Verificar si la propuesta ya fue ejecutada
        require(!propuesta.ejecutada, "La propuesta ya fue ejecutada");

        // Verificar si el votante ya ha votado
        require(
            !propuesta.haVotado[msg.sender],
            "Ya has votado en esta propuesta"
        );

        // Registrar el voto
        if (_aFavor) {
            propuesta.votosAFavor++;
        } else {
            propuesta.votosEnContra++;
        }

        // Marcar al votante como que ya ha votado
        propuesta.haVotado[msg.sender] = true;
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
            // Asegúrate de que el contrato tiene suficientes tokens para vender
            require(
                IERC20(prop.token).balanceOf(address(this)) >= prop.cantidad,
                "No hay suficientes tokens ERC20 en el contrato"
            );
            // Transfiere los tokens al destino
            require(
                IERC20(prop.token).transfer(prop.destino, prop.cantidad),
                "La transferencia de tokens ERC20 fallo"
            );
        } else if (prop.tipo == TipoPropuesta.CompraVentaERC721) {
            // Asegúrate de que el contrato posee el token ERC721
            require(
                IERC721(prop.token).ownerOf(prop.cantidad) == address(this),
                "El contrato no posee el token ERC721"
            );
            // Transfiere el token ERC721 al destino
            IERC721(prop.token).transferFrom(
                address(this),
                prop.destino,
                prop.cantidad
            );
        } else if (prop.tipo == TipoPropuesta.TransferenciaERC20) {
            // Asegúrate de que el contrato tiene suficientes tokens para transferir
            require(
                IERC20(prop.token).balanceOf(address(this)) >= prop.cantidad,
                "No hay suficientes tokens ERC20 en el contrato"
            );
            // Transfiere los tokens al destino
            require(
                IERC20(prop.token).transfer(prop.destino, prop.cantidad),
                "La transferencia de tokens ERC20 fallo"
            );
        } else if (prop.tipo == TipoPropuesta.TransferenciaERC721) {
            // Asegúrate de que el contrato posee el token ERC721
            require(
                IERC721(prop.token).ownerOf(prop.cantidad) == address(this),
                "El contrato no posee el token ERC721"
            );
            // Transfiere el token ERC721 al destino
            IERC721(prop.token).transferFrom(
                address(this),
                prop.destino,
                prop.cantidad
            );
        }

        prop.ejecutada = true;
        propuestasActivas--;
    }

    function retirarETH(
        uint256 _cantidad
    ) public soloWalletAutorizada nonReentrant {
        require(balances[msg.sender] >= _cantidad, "Fondos insuficientes");
        balances[msg.sender] -= _cantidad;
        payable(msg.sender).transfer(_cantidad);
    }

    function distribuirGanancias() public soloOwner {
        uint256 balance = address(this).balance;
        uint256 cantidadPorWallet = balance / (contadorWallets + 1); // +1 para incluir al owner

        // Asegurarse de que el balance es suficiente para distribuir a todas las wallets
        require(
            balance >= cantidadPorWallet * (contadorWallets + 1),
            "Balance insuficiente"
        );

        // Distribuir a cada wallet autorizada
        for (uint256 i = 0; i < walletsAutorizadas.length; i++) {
            balances[walletsAutorizadas[i].wallet] += cantidadPorWallet;
        }

        balances[owner] += cantidadPorWallet;
    }
}
