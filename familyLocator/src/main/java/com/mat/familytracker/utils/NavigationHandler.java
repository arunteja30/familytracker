package com.mat.familytracker.utils;


import android.app.Fragment;
import android.app.FragmentManager;
import android.app.FragmentTransaction;
import android.os.Bundle;

public class NavigationHandler {


    private static NavigationHandler instance = new NavigationHandler();
    public String currentFragmentTag;
    public Fragment currentFragment;

    private NavigationHandler() {

    }

    public static NavigationHandler getInstance() {
        return instance;
    }

    public void navigateToFragment(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment) {
        if (fragment != null) {
            String backStateName = fragment.getClass().getName();
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                if (!fragmentPopped && fragmentManager.findFragmentByTag(fragmentTag) == null) { //fragment not in back stack, create it.
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    fragmentTransaction.addToBackStack(backStateName);
                    fragmentTransaction.commit();
                    //commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                }
            }
        }
    }

    /*
       if i = 1, then create new instance for fragment.
     */
    public void navigateToFragment(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, int i) {
        if (fragment != null) {
            String backStateName = fragment.getClass().getName();
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                if (fragmentPopped && i == 1) {  // if i = 1, then create new instance for fragment
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.commit();
                }
                if (!fragmentPopped && fragmentManager.findFragmentByTag(fragmentTag) == null) { //fragment not in back stack, create it.
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    fragmentTransaction.addToBackStack(backStateName);
                    fragmentTransaction.commit();
                    //commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                }
            }
        }
    }

    public void navigateExistingFragmentWithDifferentSmartBlock(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, String itemSrc) {
        if (fragment != null) {
            String backStateName = fragment.getClass().getName() + itemSrc;
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                if (!fragmentPopped && fragmentManager.findFragmentByTag(fragmentTag) == null) { //fragment not in back stack, create it.
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    fragmentTransaction.addToBackStack(backStateName);
                    fragmentTransaction.commit();
                }
            }
        }
    }

    public void navigateToFragment(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, Bundle bundle) {
        if (fragment != null) {
            if (bundle != null) {
                fragment.setArguments(bundle);
            }
            String backStateName = fragment.getClass().getName();
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                try {
                    boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                    if (!fragmentPopped && fragmentManager.findFragmentByTag(fragmentTag) == null) { //fragment not in back stack, create it.
                        setCurrentFragment(fragment);
                        setCurrentFragmentTag(fragmentTag);
                        fragmentTransaction.replace(containerID, fragment, fragmentTag);
                        fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                        fragmentTransaction.addToBackStack(backStateName);
                        fragmentTransaction.commit();
                        //commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                    } else {
                        if (bundle != null && bundle.getString("SELECTED_SB_OPT") != null) {
                            setCurrentFragment(fragment);
                            setCurrentFragmentTag(fragmentTag);
                            fragmentTransaction.replace(containerID, fragment, fragmentTag);
                            fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                            fragmentTransaction.addToBackStack(backStateName);
                            fragmentTransaction.commit();
                        }
                    }
                } catch (Exception e) {
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    fragmentTransaction.addToBackStack(backStateName);
                    fragmentTransaction.commit();
                    // commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                }

            }

        }

    }

    public void navigateToFragment(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, Bundle bundle, boolean flag) {
        if (fragment != null) {
            if (bundle != null) {
                fragment.setArguments(bundle);
            }
            String backStateName = fragment.getClass().getName();
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                try {
                    boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                    if (!fragmentPopped) { //fragment not in back stack, create it.
                        if (fragmentManager.findFragmentByTag(fragmentTag) == null) {
                            setCurrentFragment(fragment);
                            setCurrentFragmentTag(fragmentTag);
                            fragmentTransaction.replace(containerID, fragment, fragmentTag);
                            fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                            fragmentTransaction.addToBackStack(backStateName);
                            if (flag) {
                                commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                            } else {
                                fragmentTransaction.commit();
                            }
                        } else {
                            if (bundle != null && bundle.getString("SELECTED_SB_OPT") != null) {
                                setCurrentFragment(fragment);
                                setCurrentFragmentTag(fragmentTag);
                                fragmentTransaction.replace(containerID, fragment, fragmentTag);
                                fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                                fragmentTransaction.addToBackStack(backStateName);
                                if (flag) {
                                    commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                                } else {
                                    fragmentTransaction.commit();
                                }
                            }
                        }

                    }
                } catch (Exception e) {
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    fragmentTransaction.addToBackStack(backStateName);
                    if (flag) {
                        commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                    } else {
                        fragmentTransaction.commit();
                    }
                }

            }

        }

    }

    public void navigateToFragment(int containerID, FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, boolean dirtyFix) { // DO NOT USE THIS METHOD AT ANY COST
        if (fragment != null) {
            String backStateName = fragment.getClass().getName();
            String fragmentTag = backStateName;
            if (fragmentManager != null && fragmentTransaction != null) {
                boolean fragmentPopped = fragmentManager.popBackStackImmediate(backStateName, 0);
                if ((!fragmentPopped && fragmentManager.findFragmentByTag(fragmentTag) == null) || dirtyFix) { //fragment not in back stack, create it.
                    setCurrentFragment(fragment);
                    setCurrentFragmentTag(fragmentTag);
                    fragmentTransaction.replace(containerID, fragment, fragmentTag);
                    fragmentTransaction.setTransition(FragmentTransaction.TRANSIT_FRAGMENT_FADE);
                    if (!dirtyFix)
                        fragmentTransaction.addToBackStack(backStateName);
                    fragmentTransaction.commit();
                    // commitAndExecutePendingTrans(fragmentManager, fragmentTransaction);
                }

            }

        }

    }

    public void commitAndExecutePendingTrans(FragmentManager fragmentManager, FragmentTransaction fragmentTransaction) {
        if (fragmentTransaction != null && fragmentManager != null) {
            fragmentTransaction.commit();
            fragmentManager.executePendingTransactions();
        }
    }

    public void refreshFragment(FragmentManager fragmentManager, FragmentTransaction fragmentTransaction) {

        if (fragmentManager != null && fragmentTransaction != null && getCurrentFragmentTag() != null) {
            Fragment fragment = fragmentManager.findFragmentByTag(getCurrentFragmentTag());
            if (fragment != null) {
                fragmentTransaction.detach(fragment).attach(fragment).commit();
            }
        }

    }

    public void refreshFragment(FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment) {

        if (fragmentManager != null && fragmentTransaction != null && getCurrentFragment() != null) {
            if (fragment != null && fragment.isAdded()) {
                fragmentTransaction.detach(fragment).attach(fragment).commit();
            }
        }

    }

    /*PLEASE DON'T USE THIS METHOD AS WE ARE USING ONLY FOR Trimble*/
    public void refreshFragment(FragmentManager fragmentManager, FragmentTransaction fragmentTransaction, Fragment fragment, boolean isTrimbleFix) {
        if (fragmentManager != null && fragmentTransaction != null && getCurrentFragment() != null) {
            if (fragment != null && isTrimbleFix) {
                fragmentTransaction.remove(fragment).commit();
            }
        }

    }

    public String getCurrentFragmentTag() {
        return currentFragmentTag;
    }

    public void setCurrentFragmentTag(String currentFragmentTag) {
        this.currentFragmentTag = currentFragmentTag;
    }

    public Fragment getCurrentFragment() {
        return currentFragment;
    }

    public void setCurrentFragment(Fragment currentFragment) {
        this.currentFragment = currentFragment;
    }
   /* public void popFragment(Fragment fragment, FragmentManager fragmentManager){
        FragmentTransaction trans = fragmentManager.beginTransaction();
        trans.remove(fragment);
        trans.commitAllowingStateLoss();
//        fragmentManager.popBackStack();
    }*/

    public void clearBackStack(FragmentManager fragmentManager) {

        if (fragmentManager != null && fragmentManager.getBackStackEntryCount() > 0) {
            FragmentManager.BackStackEntry first = fragmentManager.getBackStackEntryAt(0);
            fragmentManager.popBackStack(first.getId(), FragmentManager.POP_BACK_STACK_INCLUSIVE);
        }
    }

}
