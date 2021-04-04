// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../libraries/UniswapStyleLib.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IWETH.sol";
import "./BaseRouter.sol";

contract SpotRouter is BaseRouter {
    using SafeERC20 for IERC20;
    address public immutable WETH;

    constructor(address _WETH) {
        WETH = _WETH;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapStyleLib.getAmountsOut(amountIn, pairs, tokens);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SpotRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        IERC20(tokens[0]).safeTransferFrom(msg.sender, pairs[0], amounts[0]);
        _swap(amounts, pairs, tokens, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapStyleLib.getAmountsIn(amountOut, pairs, tokens);
        require(
            amounts[0] <= amountInMax,
            "SpotRouter: EXCESSIVE_INPUT_AMOUNT"
        );

        IERC20(tokens[0]).safeTransferFrom(msg.sender, pairs[0], amounts[0]);
        _swap(amounts, pairs, tokens, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(tokens[0] == WETH, "SpotRouter: INVALID_PATH");
        amounts = UniswapStyleLib.getAmountsOut(msg.value, pairs, tokens);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SpotRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairs[0], msg.value));

        _swap(amounts, pairs, tokens, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(tokens[tokens.length - 1] == WETH, "SpotRouter: INVALID_PATH");
        amounts = UniswapStyleLib.getAmountsIn(amountOut, pairs, tokens);
        require(
            amounts[0] <= amountInMax,
            "SpotRouter: EXCESSIVE_INPUT_AMOUNT"
        );

        IERC20(tokens[0]).safeTransferFrom(msg.sender, pairs[0], amounts[0]);

        _swap(amounts, pairs, tokens, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        Address.sendValue(payable(to), amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(tokens[tokens.length - 1] == WETH, "SpotRouter: INVALID_PATH");
        amounts = UniswapStyleLib.getAmountsOut(amountIn, pairs, tokens);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "SpotRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        _swap(amounts, pairs, tokens, address(this));

        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        Address.sendValue(payable(to), amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata pairs,
        address[] calldata tokens,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256[] memory amounts) {
        require(tokens[0] == WETH, "SpotRouter: INVALID_PATH");
        amounts = UniswapStyleLib.getAmountsIn(amountOut, pairs, tokens);
        require(amounts[0] <= msg.value, "SpotRouter: EXCESSIVE_INPUT_AMOUNT");

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairs[0], amounts[0]));

        _swap(amounts, pairs, tokens, to);
        // refund dust eth, if any
        if (msg.value > amounts[0])
            Address.sendValue(payable(msg.sender), msg.value - amounts[0]);
    }

    function getAmountsOut(
        uint256 inAmount,
        address[] calldata pairs,
        address[] calldata tokens
    ) external view returns (uint256[] memory) {
        return UniswapStyleLib.getAmountsOut(inAmount, pairs, tokens);
    }

    function getAmountsIn(
        uint256 outAmount,
        address[] calldata pairs,
        address[] calldata tokens
    ) external view returns (uint256[] memory) {
        return UniswapStyleLib.getAmountsIn(outAmount, pairs, tokens);
    }
}
