// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {KSJVendV2} from '../../src/ksj/KSJVendV2.sol';
import {KSJTestToken} from '../../src/ksj/KSJTestToken.sol';
interface Vm { function prank(address) external; function expectRevert(bytes4) external; function expectRevert() external; }
contract KSJVendV2Test {
  Vm constant vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));
  KSJTestToken token; KSJVendV2 machine; address buyer = address(0xB0B);
  function setUp() public {
    token=new KSJTestToken(); machine=new KSJVendV2(address(token),address(this));
    machine.configure(0,'Test item',2 ether,true);
    vm.prank(buyer);token.faucet();vm.prank(buyer);token.approve(address(machine),100 ether);
  }
  function testPurchaseConsumesEntireCompartmentAndRecordsBuyer() public {
    vm.prank(buyer);uint256 id=machine.purchase(0,2 ether);
    require(id==1); require(!machine.getSlots()[0].available);
    require(token.balanceOf(buyer)==98 ether);require(token.balanceOf(address(machine))==2 ether);
    (address who,uint8 slot,uint256 amount,bool refunded)=machine.orders(id);
    require(who==buyer&&slot==0&&amount==2 ether&&!refunded);
  }
  function testSecondBuyerCannotBuyOccupiedSale() public {
    vm.prank(buyer);machine.purchase(0,2 ether);
    vm.expectRevert(KSJVendV2.Unavailable.selector);vm.prank(buyer);machine.purchase(0,2 ether);
  }
  function testPriceChangesCannotSilentlyIncreaseCharge() public {
    machine.configure(0,'Test item',3 ether,true);
    vm.expectRevert(KSJVendV2.PriceChanged.selector);vm.prank(buyer);machine.purchase(0,2 ether);
    require(token.balanceOf(buyer)==100 ether);require(machine.getSlots()[0].available);
  }
  function testInvalidFifthCompartmentRejected() public {
    vm.expectRevert(KSJVendV2.InvalidSlot.selector);vm.prank(buyer);machine.purchase(4,2 ether);
  }
  function testOnlyOwnerCanRestock() public {
    vm.expectRevert(KSJVendV2.Unauthorized.selector);vm.prank(buyer);machine.configure(1,'Fake',1 ether,true);
  }
  function testRejectedTransferDoesNotConsumeStock() public {
    vm.prank(buyer);token.approve(address(machine),0);
    vm.expectRevert();vm.prank(buyer);machine.purchase(0,2 ether);
    require(machine.getSlots()[0].available);require(machine.nextOrderId()==1);
  }
  function testRefundReturnsTokensWithoutRestocking() public {
    vm.prank(buyer);uint256 id=machine.purchase(0,2 ether);machine.refund(id);
    require(token.balanceOf(buyer)==100 ether);require(!machine.getSlots()[0].available);
    (,,,bool refunded)=machine.orders(id);require(refunded);
    vm.expectRevert(KSJVendV2.InvalidOrder.selector);machine.refund(id);
  }
  function testBuyerCannotRefundThemselves() public {
    vm.prank(buyer);uint256 id=machine.purchase(0,2 ether);
    vm.expectRevert(KSJVendV2.Unauthorized.selector);vm.prank(buyer);machine.refund(id);
  }
  function testAllFourSlotsCanBeConfiguredIndependently() public {
    for(uint8 i=0;i<4;i++)machine.configure(i,'One item',(uint256(i)+1)*1 ether,true);
    for(uint8 i=0;i<4;i++){vm.prank(buyer);machine.purchase(i,(uint256(i)+1)*1 ether);}
    for(uint8 i=0;i<4;i++)require(!machine.getSlots()[i].available);
    require(machine.nextOrderId()==5);
  }
  function testEmptySlotsAndZeroPriceRejected() public {
    vm.expectRevert(KSJVendV2.Unavailable.selector);vm.prank(buyer);machine.purchase(1,1);
    vm.expectRevert(KSJVendV2.InvalidConfig.selector);machine.configure(0,'Test',0,true);
  }
}
